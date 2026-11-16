defmodule RescordWeb.TasksLive do
  @moduledoc """
  The tasks of an organisation, at `/o/<short name>/tasks`.

  The page shows one day, in the time zone of the organisation: today, or
  the day of `?day=2026-11-16`. On today it also lists the tasks of earlier
  days that are still due. A member takes a task, completes it, skips it
  with a reason, and opens it again. A member plans a task for any day,
  which can be months ahead. The routines page makes the tasks that repeat.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

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
     assign(socket,
       page_title: "Tasks",
       problems: [],
       kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
       residents: residents |> Enum.map(&{&1.name || "No name yet", &1.id}) |> Enum.sort(),
       groups: groups |> Enum.map(&{Residents.group_name(&1), &1.id}) |> Enum.sort(),
       locations:
         for(
           {node, depth} <- Locations.flat(tree),
           do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}
         ),
       members: members |> Enum.map(&{to_string(&1.email), &1.user_id}) |> Enum.sort(),
       can_plan?: Tasks.role_can?(socket.assigns.role, :plan)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    today = Accounts.today(socket.assigns.organisation)

    day =
      case Date.from_iso8601(params["day"] || "") do
        {:ok, date} -> date
        _not_a_date -> today
      end

    {:noreply, socket |> assign(day: day, today: today) |> assign_tasks() |> assign_form()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_tasks(socket) do
    now = DateTime.utc_now()
    options = options(socket)
    {:ok, tasks} = Tasks.day(socket.assigns.day, options)

    # The tasks of earlier days that are still due, on the page of today.
    earlier =
      if socket.assigns.day == socket.assigns.today do
        {from, _to} = Accounts.day_range(socket.assigns.organisation, socket.assigns.today)
        {:ok, overdue} = Tasks.overdue(from, options)
        overdue
      else
        []
      end

    assign(socket, tasks: tasks, earlier: earlier, now: now)
  end

  defp assign_form(socket, fields \\ nil) do
    fields = fields || %{"date" => Date.to_iso8601(socket.assigns.day), "time" => "08:00"}
    assign(socket, form: to_form(fields, as: :task))
  end

  defp path(socket) do
    base = ~p"/o/#{socket.assigns.organisation.short_name}/tasks"

    if socket.assigns.day == socket.assigns.today,
      do: base,
      else: base <> "?day=" <> Date.to_iso8601(socket.assigns.day)
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
               title: text(fields["title"]),
               note: text(fields["note"]),
               due_at: due_at,
               kind_id: text(fields["kind_id"]),
               assignee_id: text(fields["assignee_id"]),
               resident_ids: List.wrap(text(fields["resident_id"])),
               group_ids: List.wrap(text(fields["group_id"])),
               location_ids: List.wrap(text(fields["location_id"]))
             },
             options(socket)
           ) do
      day = Accounts.local_date(socket.assigns.organisation, due_at)

      {:noreply,
       push_navigate(socket,
         to: ~p"/o/#{socket.assigns.organisation.short_name}/tasks?day=#{Date.to_iso8601(day)}"
       )}
    else
      {:error, words} when is_binary(words) ->
        {:noreply, socket |> assign(problems: [words]) |> assign_form(fields)}

      {:error, error} ->
        {:noreply,
         socket |> assign(problems: Accounts.error_messages(error)) |> assign_form(fields)}
    end
  end

  def handle_event("take", %{"id" => id}, socket),
    do: act(socket, id, &Tasks.take_task(&1, options(socket)))

  def handle_event("complete", %{"id" => id}, socket),
    do: act(socket, id, &Tasks.complete_task(&1, %{}, options(socket)))

  def handle_event("reopen", %{"id" => id}, socket),
    do: act(socket, id, &Tasks.reopen_task(&1, options(socket)))

  def handle_event("skip", %{"task_id" => id, "skip" => %{"reason" => reason}}, socket),
    do: act(socket, id, &Tasks.skip_task(&1, %{skip_reason: text(reason)}, options(socket)))

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs an action on a task of this page: the page has them in hand.
  defp act(socket, id, action) do
    case Enum.find(socket.assigns.tasks ++ socket.assigns.earlier, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      task ->
        case action.(task) do
          {:ok, _task} ->
            {:noreply, push_navigate(socket, to: path(socket))}

          # The tasks are read again: another member can be the reason.
          {:error, error} ->
            {:noreply,
             socket |> assign(problems: Accounts.error_messages(error)) |> assign_tasks()}
        end
    end
  end

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  defp day_path(organisation, date),
    do: ~p"/o/#{organisation.short_name}/tasks?day=#{Date.to_iso8601(date)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Tasks
        <:subtitle>
          {TaskWords.day(@day)}{if @day == @today, do: ", today"}
        </:subtitle>
        <:actions>
          <.link patch={day_path(@organisation, Date.add(@day, -1))} data-variant="secondary">
            The day before
          </.link>
          <.link
            :if={@day != @today}
            patch={~p"/o/#{@organisation.short_name}/tasks"}
            data-variant="secondary"
          >
            Today
          </.link>
          <.link patch={day_path(@organisation, Date.add(@day, 1))} data-variant="secondary">
            The day after
          </.link>
          <.link navigate={~p"/o/#{@organisation.short_name}/routines"} data-variant="secondary">
            Routines
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section :if={@earlier != []} aria-labelledby="earlier-heading">
        <h2 id="earlier-heading">Still due from earlier days</h2>
        <.tasks
          tasks={@earlier}
          organisation={@organisation}
          members={@members}
          user={@current_user}
          role={@role}
          now={@now}
          with_day
        />
      </section>

      <section aria-labelledby="day-heading">
        <h2 id="day-heading">Tasks of the day</h2>
        <p :if={@tasks == []}>There is no task on this day.</p>
        <.tasks
          :if={@tasks != []}
          tasks={@tasks}
          organisation={@organisation}
          members={@members}
          user={@current_user}
          role={@role}
          now={@now}
        />
      </section>

      <details :if={@can_plan?} id="new-task">
        <summary>New task</summary>
        <.form for={@form} id="task" phx-submit="plan">
          <.input field={@form[:title]} type="text" label="What to do" maxlength="120" required />
          <.input
            field={@form[:kind_id]}
            type="select"
            label="Kind"
            prompt="Not recorded"
            options={@kinds}
          />
          <.input field={@form[:date]} type="date" label="Day" required />
          <.input field={@form[:time]} type="time" label="Time" required />
          <.input
            field={@form[:resident_id]}
            type="select"
            label="For a resident"
            prompt="No resident"
            options={@residents}
          />
          <.input
            field={@form[:group_id]}
            type="select"
            label="For a group"
            prompt="No group"
            options={@groups}
          />
          <.input
            field={@form[:location_id]}
            type="select"
            label="For a location"
            prompt="No location"
            options={@locations}
          />
          <.input
            field={@form[:assignee_id]}
            type="select"
            label="Who does it"
            prompt="Anybody"
            options={@members}
          />
          <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
          <footer><.button type="submit">Plan the task</.button></footer>
        </.form>
      </details>
    </Layouts.app>
    """
  end

  attr :tasks, :list, required: true
  attr :organisation, :map, required: true
  attr :members, :list, required: true
  attr :user, :map, required: true
  attr :role, :atom, required: true
  attr :now, :any, required: true
  attr :with_day, :boolean, default: false, doc: "shows the day of each task with its time"

  # A table of tasks, each with its state and what a member can do with it.
  defp tasks(assigns) do
    ~H"""
    <div data-scroll>
      <table>
        <thead>
          <tr>
            <th scope="col">Due</th>
            <th scope="col">Task</th>
            <th scope="col">For</th>
            <th scope="col">Who</th>
            <th scope="col">State</th>
            <th scope="col">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={task <- @tasks} id={"task-#{task.id}"}>
            <td>{due(task, @organisation, @with_day)}</td>
            <td>
              {task.title}
              <small :if={task.kind}>{task.kind.label}</small>
              <small :if={task.routine_id}>From a routine</small>
              <small :if={task.note}>{task.note}</small>
              <small :if={task.skip_reason}>Skipped: {task.skip_reason}</small>
            </td>
            <td>{for_words(task)}</td>
            <td>{who(task, @members)}</td>
            <td>
              <.state kind={TaskWords.phase_kind(Tasks.phase(task, @now))}>
                {TaskWords.phase(Tasks.phase(task, @now))}
              </.state>
            </td>
            <td>
              <.button
                :if={
                  task.state == :due and task.assignee_id != @user.id and
                    Tasks.role_can?(@role, :take)
                }
                phx-click="take"
                phx-value-id={task.id}
                aria-label={"Take the task #{task.title}"}
              >
                Take
              </.button>
              <.button
                :if={task.state == :due and Tasks.role_can?(@role, :complete)}
                phx-click="complete"
                phx-value-id={task.id}
                aria-label={"Mark the task #{task.title} as done"}
              >
                Done
              </.button>
              <.button
                :if={task.state != :due and Tasks.role_can?(@role, :reopen)}
                phx-click="reopen"
                phx-value-id={task.id}
                aria-label={"Open the task #{task.title} again"}
              >
                Open again
              </.button>
              <details
                :if={task.state == :due and Tasks.role_can?(@role, :skip)}
                id={"skip-details-#{task.id}"}
              >
                <summary>Skip</summary>
                <form id={"skip-#{task.id}"} phx-submit="skip">
                  <input type="hidden" name="task_id" value={task.id} />
                  <.input
                    id={"skip-#{task.id}-reason"}
                    name="skip[reason]"
                    type="text"
                    label={"Why you skip #{task.title}"}
                    value=""
                    maxlength="200"
                    required
                  />
                  <.button type="submit">Skip the task</.button>
                </form>
              </details>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp due(task, organisation, with_day?) do
    local = Accounts.local_time(organisation, task.due_at)

    if with_day?,
      do: "#{RescordWeb.ResidentWords.date(DateTime.to_date(local))}, #{TaskWords.time(local)}",
      else: TaskWords.time(local)
  end

  defp for_words(task) do
    case Tasks.subject_names(task) do
      [] -> "Nothing in particular"
      names -> Enum.join(names, ", ")
    end
  end

  defp who(%{assignee_id: nil}, _members), do: "Anybody"

  defp who(%{assignee_id: id}, members) do
    Enum.find_value(members, "A person who is not a member now", fn {email, user_id} ->
      if user_id == id, do: email
    end)
  end
end
