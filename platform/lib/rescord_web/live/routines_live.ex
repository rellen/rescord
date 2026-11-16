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

  alias Rescord.{Accounts, Journal, Lists, Locations, Residents, Tasks}
  alias RescordWeb.{ResidentWords, TaskWords}

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
    assign(socket,
      form: to_form(fields, as: :routine),
      pattern: fields["pattern"],
      weekdays: List.wrap(fields["weekdays"])
    )
  end

  # The facts of a routine from the fields of the form. Ash reads each value:
  # a pattern that it does not know is an error, and no atom.
  defp facts(fields) do
    %{
      title: text(fields["title"]),
      note: text(fields["note"]),
      kind_id: text(fields["kind_id"]),
      assignee_id: text(fields["assignee_id"]),
      pattern: text(fields["pattern"]),
      every: text(fields["every"]),
      weekdays: fields["weekdays"] |> List.wrap() |> Enum.filter(&is_binary/1),
      times: for(field <- @time_fields, time = time(fields[field]), do: time),
      starts_on: text(fields["starts_on"]),
      ends_on: text(fields["ends_on"]),
      days_ahead: text(fields["days_ahead"]),
      resident_ids: List.wrap(text(fields["resident_id"])),
      group_ids: List.wrap(text(fields["group_id"])),
      location_ids: List.wrap(text(fields["location_id"]))
    }
  end

  # A time of a form is `08:00`. A value that is no time stays as it is, and
  # Ash refuses it.
  defp time(value) do
    case text(value) do
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

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  defp edit_path(organisation, routine),
    do: ~p"/o/#{organisation.short_name}/routines/#{routine.id}/edit"

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

      <section :if={@editing} aria-labelledby="edit-heading">
        <h2 id="edit-heading">Change the routine {@editing.title}</h2>
        <p>
          When you save, Rescord cancels the tasks of this routine that are due after now, and
          makes them again. The tasks that are done, skipped or late stay as they are.
        </p>
        <.routine_form {assigns} button="Save the routine" />
        <p><.link navigate={~p"/o/#{@organisation.short_name}/routines"}>Change nothing</.link></p>
      </section>

      <section :if={!@editing} aria-labelledby="routines-heading">
        <h2 id="routines-heading">The routines</h2>
        <p :if={@routines == []}>There is no routine yet.</p>
        <div :if={@routines != []} data-scroll>
          <table>
            <thead>
              <tr>
                <th scope="col">Routine</th>
                <th scope="col">When</th>
                <th scope="col">For</th>
                <th scope="col">Who</th>
                <th scope="col">State</th>
                <th scope="col">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={routine <- @routines} id={"routine-#{routine.id}"}>
                <td>
                  {routine.title}
                  <small :if={routine.kind}>{routine.kind.label}</small>
                  <small :if={routine.prescription_id}>Writes a dose to the journal</small>
                  <small :if={routine.note}>{routine.note}</small>
                </td>
                <td>
                  {TaskWords.pattern(routine)}, at {TaskWords.times(routine.times)}
                  <small>{TaskWords.span(routine)}</small>
                </td>
                <td>{for_words(routine, assigns)}</td>
                <td>{who(routine, @members)}</td>
                <td>
                  <.state kind={state_kind(routine, @today)}>{state_words(routine, @today)}</.state>
                  <small :if={next = Tasks.next_task_at(routine)}>
                    Next: {next_words(next, @organisation)}
                  </small>
                </td>
                <td>
                  <.change_link
                    :if={@can_revise?}
                    to={edit_path(@organisation, routine)}
                    label={"Change the routine #{routine.title}"}
                  />
                  <.button
                    :if={@can_revise? and not routine.paused}
                    phx-click="pause"
                    phx-value-id={routine.id}
                    aria-label={"Stop the routine #{routine.title} for a time"}
                  >
                    Pause
                  </.button>
                  <.button
                    :if={@can_revise? and routine.paused}
                    phx-click="resume"
                    phx-value-id={routine.id}
                    aria-label={"Start the routine #{routine.title} again"}
                  >
                    Start again
                  </.button>
                  <details :if={@can_remove?} id={"end-details-#{routine.id}"}>
                    <summary>End</summary>
                    <form id={"end-#{routine.id}"} phx-submit="remove">
                      <input type="hidden" name="routine_id" value={routine.id} />
                      <p>
                        The routine goes, with its tasks that are due after now. The tasks that
                        are done, skipped or late stay.
                      </p>
                      <.button type="submit">End the routine {routine.title}</.button>
                    </form>
                  </details>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <details :if={!@editing and @can_start?} id="new-routine" open={@prescription != nil}>
        <summary>New routine</summary>
        <.routine_form {assigns} button="Start the routine" />
      </details>
    </Layouts.app>
    """
  end

  attr :to, :string, required: true
  attr :label, :string, required: true

  # The link is on one line: a space before its end is drawn with the line
  # under the link.
  defp change_link(assigns) do
    ~H"""
    <.link navigate={@to} aria-label={@label}>Change</.link>
    """
  end

  attr :form, :any, required: true
  attr :button, :string, required: true
  attr :pattern, :string, required: true
  attr :weekdays, :list, required: true
  attr :prescription, :any, required: true
  attr :days_ahead, :integer, required: true
  attr :kinds, :list, required: true
  attr :residents, :list, required: true
  attr :groups, :list, required: true
  attr :locations, :list, required: true
  attr :members, :list, required: true
  attr :problems, :list, required: true
  attr :refused_form?, :boolean, required: true
  attr :rest, :global

  # The form of a routine: a new one, or one that a member changes.
  defp routine_form(assigns) do
    ~H"""
    <.form for={@form} id="routine" phx-change="shape" phx-submit="save">
      <.problems :if={@refused_form?} list={@problems} />
      <p :if={@prescription} id="routine-prescription">
        Each task of this routine writes a dose of {@prescription.medication} ({@prescription.dose}) for {@prescription.resident_name} to the journal, when a member
        completes it.
      </p>
      <.input field={@form[:title]} type="text" label="What to do" maxlength="120" required />
      <.input
        field={@form[:kind_id]}
        type="select"
        label="Kind"
        prompt="Not recorded"
        options={@kinds}
      />
      <.input
        field={@form[:pattern]}
        type="select"
        label="How it repeats"
        options={TaskWords.pattern_options()}
      />
      <fieldset :if={@pattern == "weekly"} id="routine-weekdays">
        <legend>Days of the week</legend>
        <label :for={{name, number} <- TaskWords.weekdays()}>
          <input
            type="checkbox"
            name="routine[weekdays][]"
            value={number}
            checked={to_string(number) in @weekdays}
          />
          {name}
        </label>
      </fieldset>
      <.input
        :if={@pattern in ["interval", "monthly"]}
        field={@form[:every]}
        type="number"
        label={if @pattern == "interval", do: "Every how many days", else: "Every how many months"}
        min="1"
        max={if @pattern == "interval", do: "366", else: "36"}
        required
      />
      <.input field={@form[:time_1]} type="time" label="Time" required />
      <.input field={@form[:time_2]} type="time" label="A second time, if there is one" />
      <.input field={@form[:time_3]} type="time" label="A third time, if there is one" />
      <.input field={@form[:time_4]} type="time" label="A fourth time, if there is one" />
      <.input field={@form[:starts_on]} type="date" label="First day" required />
      <.input field={@form[:ends_on]} type="date" label="Last day, if there is one" />
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
      <.input
        field={@form[:days_ahead]}
        type="number"
        label={"How many days ahead the tasks exist, if not #{@days_ahead}"}
        min="1"
        max="400"
      />
      <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
      <footer><.button type="submit">{@button}</.button></footer>
    </.form>
    """
  end

  defp for_words(routine, assigns) do
    names =
      names(routine.resident_ids, assigns.residents, "A resident who is not here now") ++
        names(routine.group_ids, assigns.groups, "A group that is not here now") ++
        names(routine.location_ids, assigns.locations, "A location that is not here now")

    if names == [], do: "Nothing in particular", else: Enum.join(names, ", ")
  end

  defp names(ids, options, missing) do
    for id <- ids do
      Enum.find_value(options, missing, fn {name, option_id} ->
        if option_id == id, do: String.trim_leading(name, "– ")
      end)
    end
  end

  defp who(%{assignee_id: nil}, _members), do: "Anybody"

  defp who(%{assignee_id: id}, members) do
    Enum.find_value(members, "A person who is not a member now", fn {email, user_id} ->
      if user_id == id, do: email
    end)
  end

  defp ended?(%{ends_on: %Date{} = ends_on}, today), do: Date.compare(ends_on, today) == :lt
  defp ended?(_routine, _today), do: false

  defp state_words(%{paused: true}, _today), do: "Paused"

  defp state_words(routine, today) do
    cond do
      ended?(routine, today) -> "Finished"
      Date.compare(routine.starts_on, today) == :gt -> "Not started"
      true -> "Active"
    end
  end

  defp state_kind(%{paused: true}, _today), do: "none"

  defp state_kind(routine, today) do
    cond do
      ended?(routine, today) -> "none"
      Date.compare(routine.starts_on, today) == :gt -> "info"
      true -> "ok"
    end
  end

  defp next_words(instant, organisation) do
    local = Accounts.local_time(organisation, instant)
    "#{ResidentWords.date(DateTime.to_date(local))}, #{TaskWords.time(local)}"
  end
end
