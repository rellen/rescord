defmodule RescordWeb.TasksLive do
  @moduledoc """
  The tasks of an organisation, at `/o/<short name>/tasks`.

  The page shows one day, in the time zone of the organisation: today, or
  the day of `?day=2026-11-16`. On today it also lists the tasks of earlier
  days that are still due. A member takes a task, completes it, skips it
  with a reason, and opens it again. A member plans a task for any day,
  which can be months ahead. The routines page makes the tasks that repeat.

  The tasks are a collection of Cinder (ADR 0097): a search on the title,
  filters on the state, the kind and the person, and pages, all in the
  address (ADR 0084), so `?state=due&who=me` is what is left for the person.
  Cinder reads those parameters. The page reads only `day`, and gives the
  others back in the links to another day. It does not hold the tasks: an
  event reads its task again with `Rescord.Tasks.task_of_day/3`.

  The collection reads again when a task changes (ADR 0096), so a member
  sees at once that another member took a task or finished it. A task is
  not temporal, so the query reads the present.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  import RescordWeb.TaskComponents

  alias Rescord.{Accounts, Lists, Locations, Residents, Tasks}
  alias RescordWeb.TaskWords

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
    {:ok, kinds} = Lists.offered_values(:task_kind, options)
    {:ok, residents} = Residents.residents([load: [:name]] ++ options)
    {:ok, groups} = Residents.groups_with_facts(options)
    {:ok, tree} = Locations.tree(options)
    {:ok, members} = Accounts.members([load: [:email]] ++ options)

    {:ok,
     socket
     |> LiveChanges.listen([Tasks], &read_again/1)
     |> assign(
       page_title: "Tasks",
       problems: [],
       refused_form?: false,
       kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
       residents:
         residents |> Enum.map(&{&1.name || "A resident with no name", &1.id}) |> Enum.sort(),
       groups: groups |> Enum.map(&{Residents.group_name(&1), &1.id}) |> Enum.sort(),
       locations:
         for(
           {node, depth} <- Locations.flat(tree),
           do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}
         ),
       members: members |> Enum.map(&{to_string(&1.email), &1.user_id}) |> Enum.sort(),
       all_kinds: all_kinds(options),
       people: Accounts.labels(options),
       for_person: &for_person(&1, &2, socket.assigns.current_user.id),
       can_plan?: Tasks.role_can?(socket.assigns.role, :plan)
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    today = Accounts.today(socket.assigns.organisation)

    day =
      case Date.from_iso8601(params["day"] || "") do
        {:ok, date} -> date
        _not_a_date -> today
      end

    {:noreply,
     socket
     |> assign(day: day, today: today, now: DateTime.utc_now(), query: query_of(uri))
     |> assign_form()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # After a change of another person (ADR 0096): the rows stay on the page
  # while Cinder reads.
  defp read_again(socket) do
    socket
    |> assign(now: DateTime.utc_now())
    |> Cinder.refresh_table("tasks", silent: true)
  end

  # The options of the query of the day: the page of today has the tasks of
  # earlier days that are still due too.
  defp day_options(assigns) do
    [
      actor: assigns.current_user,
      tenant: assigns.organisation,
      earlier: assigns.day == assigns.today
    ]
  end

  # The parameters of the address, as the browser sent them. The page reads
  # none of the parameters of Cinder: it gives them back in the links to
  # another day, so the search and the filters stay.
  defp query_of(uri) when is_binary(uri), do: URI.decode_query(URI.parse(uri).query || "")

  # Each kind of task of the organisation, as the choices of the filter. A
  # kind that an administrator retired is one of them: a task can still
  # have it.
  defp all_kinds(options) do
    case Lists.values(:task_kind, options) do
      {:ok, values} -> Enum.map(values, &{to_string(&1.label), &1.id})
      {:error, _error} -> []
    end
  end

  # The filter "Who". The value comes from the address or from the form of
  # the filter, and Cinder passes only a value of its options.
  defp for_person(query, %{value: "me"}, user_id), do: Tasks.for_person(query, user_id)
  defp for_person(query, %{value: "anybody"}, _user_id), do: Tasks.for_person(query, :anybody)

  defp for_person(query, %{value: value}, _user_id) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> Tasks.for_person(query, id)
      :error -> query
    end
  end

  defp for_person(query, _filter, _user_id), do: query

  defp assign_form(socket, fields \\ nil, error \\ nil) do
    fields = fields || %{"date" => Date.to_iso8601(socket.assigns.day), "time" => "08:00"}
    assign(socket, form: typed_form(fields, as: :task, error: error))
  end

  # The address of the tasks of a day, with the search and the filters of
  # `query`. Today has no `day`.
  defp tasks_path(assigns, query) do
    base = ~p"/o/#{assigns.organisation.short_name}/tasks"

    case query do
      empty when map_size(empty) == 0 -> base
      query -> base <> "?" <> URI.encode_query(query)
    end
  end

  # The address of another day, with the search and the filters, from its
  # first page.
  defp day_path(assigns, date) do
    query = Map.drop(assigns.query, ["day", "page"])

    if date == assigns.today,
      do: tasks_path(assigns, query),
      else: tasks_path(assigns, Map.put(query, "day", Date.to_iso8601(date)))
  end

  @impl true
  def handle_event("plan", %{"task" => fields}, socket) when is_map(fields) do
    with {:ok, due_at} <-
           Accounts.local_instant(
             socket.assigns.organisation,
             "#{fields["date"]}T#{fields["time"]}"
           ),
         {:ok, _task} <-
           Tasks.plan_task(
             %{
               title: non_blank(fields["title"]),
               note: non_blank(fields["note"]),
               due_at: due_at,
               kind_id: non_blank(fields["kind_id"]),
               assignee_ids: members(fields),
               resident_ids: List.wrap(non_blank(fields["resident_id"])),
               group_ids: List.wrap(non_blank(fields["group_id"])),
               location_ids: List.wrap(non_blank(fields["location_id"]))
             },
             options(socket)
           ) do
      day = Accounts.local_date(socket.assigns.organisation, due_at)

      {:noreply,
       socket
       |> put_flash(:info, "The task is added.")
       |> push_navigate(
         to: ~p"/o/#{socket.assigns.organisation.short_name}/tasks?day=#{Date.to_iso8601(day)}"
       )}
    else
      {:error, error} ->
        {:noreply,
         socket
         |> assign(
           problems: Accounts.error_messages(error),
           refused_form?: socket.assigns.can_plan?
         )
         |> assign_form(fields, error)}
    end
  end

  def handle_event("take", %{"id" => id}, socket),
    do: act(socket, id, "is yours", &Tasks.take_task(&1, options(socket)))

  def handle_event("complete", %{"id" => id}, socket),
    do: act(socket, id, "is done", &Tasks.complete_task(&1, %{}, options(socket)))

  def handle_event("reopen", %{"id" => id}, socket),
    do: act(socket, id, "is open again", &Tasks.reopen_task(&1, options(socket)))

  def handle_event("skip", %{"task_id" => id, "skip" => %{"reason" => reason}}, socket),
    do:
      act(
        socket,
        id,
        "is skipped",
        &Tasks.skip_task(&1, %{skip_reason: non_blank(reason)}, options(socket))
      )

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The members of a form: each id that the browser sent. Ash refuses an id
  # that is no id.
  defp members(fields),
    do:
      fields["assignee_ids"]
      |> List.wrap()
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 == ""))

  # Runs an action on a task that the page shows. The page does not hold
  # the tasks, so it reads the task again, as the person, from the tasks of
  # this day alone. Then the collection reads again, and keeps its search,
  # its filters and its page. After a refusal it shows the task as it is
  # now: another member can be the reason. After a write it says what it did
  # (issue 35): "The task Feed the hens is done."
  defp act(socket, id, done, action) when is_binary(id) do
    with {:ok, %{} = task} <-
           Tasks.task_of_day(socket.assigns.day, id, day_options(socket.assigns)) do
      socket =
        case action.(task) do
          {:ok, _task} ->
            socket
            |> assign(problems: [])
            |> put_flash(:info, "The task #{task.title} #{done}.")

          {:error, error} ->
            assign(socket, problems: Accounts.error_messages(error))
        end

      {:noreply,
       socket
       |> assign(refused_form?: false, now: DateTime.utc_now())
       |> Cinder.Refresh.refresh_table("tasks")}
    else
      _not_on_the_page -> {:noreply, socket}
    end
  end

  defp act(socket, _id, _done, _action), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:tasks}
    >
      <.header icon={Icons.section(:tasks)}>
        Tasks
        <:subtitle>
          {TaskWords.day(@day)}{if @day == @today, do: ", today"}
        </:subtitle>
        <:actions>
          <.link patch={day_path(assigns, Date.add(@day, -1))} data-variant="secondary">
            <.icon name="chevron-left" /> The day before
          </.link>
          <.link
            :if={@day != @today}
            patch={day_path(assigns, @today)}
            data-variant="secondary"
          >
            <.icon name="calendar" /> Today
          </.link>
          <.link patch={day_path(assigns, Date.add(@day, 1))} data-variant="secondary">
            The day after <.icon name="chevron-right" />
          </.link>
          <.link
            :if={@ruby?}
            navigate={~p"/o/#{@organisation.short_name}/ruby"}
            data-variant="secondary"
            id="ask-ruby"
          >
            <.icon name={Icons.section(:ruby)} /> Ask Ruby
          </.link>
          <.link navigate={~p"/o/#{@organisation.short_name}/routines"} data-variant="secondary">
            <.icon name={Icons.section(:routines)} /> Routines
          </.link>
          <.link navigate={~p"/o/#{@organisation.short_name}/calendar"} data-variant="secondary">
            <.icon name={Icons.section(:calendar)} /> Calendar feeds
          </.link>
          <RescordWeb.ReportComponents.report_link
            id="task-sheet"
            icon="printer"
            href={~p"/o/#{@organisation.short_name}/reports/tasks.pdf?#{[on: Date.to_iso8601(@day)]}"}
          >
            Sheet (PDF)
          </RescordWeb.ReportComponents.report_link>
        </:actions>
      </.header>

      <.problems :if={not @refused_form?} list={@problems} />

      <.new_task
        :if={@can_plan?}
        refused_form?={@refused_form?}
        problems={@problems}
        form={@form}
        kinds={@kinds}
        residents={@residents}
        groups={@groups}
        locations={@locations}
        members={@members}
      />

      <.tasks
        day={@day}
        today={@today}
        query={Tasks.query_to_day(@day, day_options(assigns))}
        url_state={@url_state}
        organisation={@organisation}
        members={@members}
        kinds={@all_kinds}
        people={@people}
        for_person={@for_person}
        user={@current_user}
        role={@role}
        now={@now}
      />
    </Layouts.app>
    """
  end
end
