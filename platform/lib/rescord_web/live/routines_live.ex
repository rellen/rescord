defmodule RescordWeb.RoutinesLive do
  @moduledoc """
  The routines of an organisation, at `/o/<short name>/routines`: the tasks
  that repeat (ADR 0033). A member starts a routine, changes one at
  `/o/<short name>/routines/<id>/edit`, stops one for a time, and ends one.

  `?prescription=<id>` opens the form for a routine that gives the doses of
  a prescription. The journal page links to it.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.RoutineComponents

  alias Rescord.{Accounts, Journal, Lists, Locations, Residents, Tasks}
  alias RescordWeb.TaskWords

  # The fields of the times of the form: a routine of the page has 4 at most.
  @time_fields ~w(time_1 time_2 time_3 time_4)

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
       page_title: "Routines",
       problems: [],
       refused_form?: false,
       kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}),
       residents: residents |> Enum.map(&{&1.name || "No name yet", &1.id}) |> Enum.sort(),
       groups: groups |> Enum.map(&{Residents.group_name(&1), &1.id}) |> Enum.sort(),
       locations:
         for(
           {node, depth} <- Locations.flat(tree),
           do: {String.duplicate("– ", depth) <> node.location.name, node.location.id}
         ),
       members: members |> Enum.map(&{to_string(&1.email), &1.user_id}) |> Enum.sort(),
       can_start?: Tasks.role_can_routine?(socket.assigns.role, :start),
       can_revise?: Tasks.role_can_routine?(socket.assigns.role, :revise),
       can_remove?: Tasks.role_can_routine?(socket.assigns.role, :remove)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    options = options(socket)
    now = DateTime.utc_now()
    {:ok, routines} = Tasks.routines_with_facts(now, options)

    socket =
      assign(socket,
        routines: routines,
        today: Accounts.today(socket.assigns.organisation),
        days_ahead: socket.assigns.organisation.task_days_ahead
      )

    case socket.assigns.live_action do
      :edit ->
        case Enum.find(routines, &(&1.id == params["id"])) do
          nil ->
            {:noreply, push_navigate(socket, to: path(socket))}

          routine ->
            {:noreply,
             socket
             |> assign(
               editing: routine,
               prescription: prescription(routine.prescription_id, options)
             )
             |> assign_form(fields_of(routine))}
        end

      _index ->
        prescription = prescription(params["prescription"], options)

        {:noreply,
         socket
         |> assign(editing: nil, prescription: prescription)
         |> assign_form(new_fields(socket.assigns.today, prescription))}
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp path(socket), do: ~p"/o/#{socket.assigns.organisation.short_name}/routines"

  # The prescription that a routine gives the doses of, with its resident,
  # or `nil`: the member reads it with their own grants.
  defp prescription(id, options) when is_binary(id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = entry} <- Journal.entry_of_prescription(id, options),
         {:ok, %{prescription: %{} = prescription}} <-
           Journal.entry_with_facts(entry.id, options),
         {:ok, %{} = resident} <-
           Residents.resident(entry.resident_id, [load: [:name]] ++ options) do
      %{
        id: prescription.id,
        medication: prescription.medication,
        dose: prescription.dose,
        resident_id: resident.id,
        resident_name: resident.name || "a resident with no name"
      }
    else
      _nothing -> nil
    end
  end

  defp prescription(_id, _options), do: nil

  defp new_fields(today, prescription) do
    fields = %{
      "pattern" => "daily",
      "time_1" => "08:00",
      "starts_on" => Date.to_iso8601(today),
      "weekdays" => []
    }

    if prescription do
      Map.merge(fields, %{
        "title" => String.slice("Medicate: #{prescription.medication}", 0, 120),
        "resident_id" => prescription.resident_id
      })
    else
      fields
    end
  end

  # A routine as the fields of the form.
  defp fields_of(routine) do
    times =
      routine.times
      |> Enum.zip(@time_fields)
      |> Map.new(fn {time, field} -> {field, Calendar.strftime(time, "%H:%M")} end)

    Map.merge(times, %{
      "title" => routine.title,
      "note" => routine.note,
      "kind_id" => routine.kind_id,
      "assignee_id" => routine.assignee_id,
      "pattern" => to_string(routine.pattern),
      "every" => routine.every && to_string(routine.every),
      "weekdays" => Enum.map(routine.weekdays, &to_string/1),
      "starts_on" => Date.to_iso8601(routine.starts_on),
      "ends_on" => routine.ends_on && Date.to_iso8601(routine.ends_on),
      "days_ahead" => routine.days_ahead && to_string(routine.days_ahead),
      "resident_id" => List.first(routine.resident_ids),
      "group_id" => List.first(routine.group_ids),
      "location_id" => List.first(routine.location_ids)
    })
  end

  defp assign_form(socket, fields) do
    fields = typed_fields(fields)

    assign(socket,
      form: typed_form(fields, as: :routine),
      pattern: fields["pattern"],
      weekdays: List.wrap(fields["weekdays"])
    )
  end

  # The facts of a routine from the fields of the form. Ash reads each value:
  # a pattern that it does not know is an error, and no atom.
  defp facts(fields) do
    %{
      title: non_blank(fields["title"]),
      note: non_blank(fields["note"]),
      kind_id: non_blank(fields["kind_id"]),
      assignee_id: non_blank(fields["assignee_id"]),
      pattern: non_blank(fields["pattern"]),
      every: non_blank(fields["every"]),
      weekdays: fields["weekdays"] |> List.wrap() |> Enum.filter(&is_binary/1),
      times: for(field <- @time_fields, time = time(fields[field]), do: time),
      starts_on: non_blank(fields["starts_on"]),
      ends_on: non_blank(fields["ends_on"]),
      days_ahead: non_blank(fields["days_ahead"]),
      resident_ids: List.wrap(non_blank(fields["resident_id"])),
      group_ids: List.wrap(non_blank(fields["group_id"])),
      location_ids: List.wrap(non_blank(fields["location_id"]))
    }
  end

  # A time of a form is `08:00`. A value that is no time stays as it is, and
  # Ash refuses it.
  defp time(value) do
    case non_blank(value) do
      nil -> nil
      <<_hour::binary-size(2), ":", _minute::binary-size(2)>> = short -> short <> ":00"
      other -> other
    end
  end

  @impl true
  def handle_event("shape", %{"routine" => fields}, socket) when is_map(fields),
    do: {:noreply, assign_form(socket, fields)}

  def handle_event("save", %{"routine" => fields}, socket) when is_map(fields) do
    options = options(socket)

    result =
      case socket.assigns.editing do
        nil ->
          facts = fields |> facts() |> Map.put(:prescription_id, prescription_id(socket))
          Tasks.start_routine(facts, options)

        routine ->
          Tasks.revise_routine(routine, facts(fields), options)
      end

    case result do
      {:ok, _routine} ->
        {:noreply, push_navigate(socket, to: path(socket))}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(
           problems: Accounts.error_messages(error),
           # The form is on the page of a person who can start or change a routine.
           refused_form?: socket.assigns.can_start? or not is_nil(socket.assigns.editing)
         )
         |> assign_form(fields)}
    end
  end

  def handle_event("pause", %{"id" => id}, socket),
    do: act(socket, id, &Tasks.pause_routine(&1, options(socket)))

  def handle_event("resume", %{"id" => id}, socket),
    do: act(socket, id, &Tasks.resume_routine(&1, options(socket)))

  def handle_event("remove", %{"routine_id" => id}, socket),
    do: act(socket, id, &Tasks.remove_routine(&1, options(socket)))

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp prescription_id(%{assigns: %{prescription: %{id: id}}}), do: id
  defp prescription_id(_socket), do: nil

  # Runs an action on a routine of this page: the page has them in hand.
  defp act(socket, id, action) do
    case Enum.find(socket.assigns.routines, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      routine ->
        case action.(routine) do
          {:error, error} ->
            {:noreply,
             assign(socket, problems: Accounts.error_messages(error), refused_form?: false)}

          _done ->
            {:noreply, push_navigate(socket, to: path(socket))}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Routines
        <:subtitle>
          The tasks that repeat. Rescord makes the tasks of a routine {TaskWords.days(@days_ahead)} ahead.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/o/#{@organisation.short_name}/tasks"} data-variant="secondary">
            The tasks of today
          </.link>
        </:actions>
      </.header>

      <.problems :if={not @refused_form?} list={@problems} />

      <.edit_routine
        :if={@editing}
        editing={@editing}
        form={@form}
        pattern={@pattern}
        weekdays={@weekdays}
        prescription={@prescription}
        days_ahead={@days_ahead}
        kinds={@kinds}
        residents={@residents}
        groups={@groups}
        locations={@locations}
        members={@members}
        problems={@problems}
        refused_form?={@refused_form?}
        organisation={@organisation}
      />

      <.routines_table
        :if={!@editing}
        routines={@routines}
        residents={@residents}
        groups={@groups}
        locations={@locations}
        members={@members}
        today={@today}
        organisation={@organisation}
        can_revise?={@can_revise?}
        can_remove?={@can_remove?}
      />

      <.new_routine
        :if={!@editing and @can_start?}
        prescription={@prescription}
        form={@form}
        pattern={@pattern}
        weekdays={@weekdays}
        days_ahead={@days_ahead}
        kinds={@kinds}
        residents={@residents}
        groups={@groups}
        locations={@locations}
        members={@members}
        problems={@problems}
        refused_form?={@refused_form?}
      />
    </Layouts.app>
    """
  end
end
