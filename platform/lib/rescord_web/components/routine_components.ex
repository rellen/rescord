defmodule RescordWeb.RoutineComponents do
  @moduledoc """
  The parts of the page of the routines (ADR 0033 and ADR 0037): the list
  of the routines, and the form of a routine.
  """

  use RescordWeb, :html

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.{ResidentWords, TaskWords}

  @doc "The form that changes a routine, on its own page."
  attr :editing, :any, required: true
  attr :form, :any, required: true
  attr :pattern, :any, required: true
  attr :weekdays, :any, required: true
  attr :prescription, :any, required: true
  attr :days_ahead, :any, required: true
  attr :kinds, :any, required: true
  attr :residents, :any, required: true
  attr :groups, :any, required: true
  attr :locations, :any, required: true
  attr :members, :any, required: true
  attr :problems, :any, required: true
  attr :refused_form?, :any, required: true
  attr :organisation, :any, required: true

  def edit_routine(assigns) do
    ~H"""
    <section aria-labelledby="edit-heading">
      <h2 id="edit-heading">Change the routine {@editing.title}</h2>
      <p>
        When you save, Rescord cancels the tasks of this routine that are due after now, and
        makes them again. The tasks that are done, skipped or late stay as they are.
      </p>
      <.routine_form
        button="Save the routine"
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
      />
      <p><.link navigate={~p"/o/#{@organisation.short_name}/routines"}>Change nothing</.link></p>
    </section>
    """
  end

  @doc "The routines, each with when it repeats, what it is for, its state and its actions."
  attr :routines, :any, required: true
  attr :residents, :any, required: true
  attr :groups, :any, required: true
  attr :locations, :any, required: true
  attr :members, :any, required: true
  attr :today, :any, required: true
  attr :organisation, :any, required: true
  attr :can_revise?, :any, required: true
  attr :can_remove?, :any, required: true

  def routines_table(assigns) do
    ~H"""
    <section aria-labelledby="routines-heading">
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
              <td data-label="When">
                {TaskWords.pattern(routine)}, at {TaskWords.times(routine.times)}
                <small>{TaskWords.span(routine)}</small>
              </td>
              <td data-label="For">{for_words(routine, @residents, @groups, @locations)}</td>
              <td data-label="Who">{who(routine, @members)}</td>
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
                  aria-label={"Pause the routine #{routine.title}"}
                >
                  Pause
                </.button>
                <.button
                  :if={@can_revise? and routine.paused}
                  phx-click="resume"
                  phx-value-id={routine.id}
                  aria-label={"Start again the routine #{routine.title}"}
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
    """
  end

  @doc "The form of a new routine, in a part of the page that is closed at first."
  attr :prescription, :any, required: true
  attr :form, :any, required: true
  attr :pattern, :any, required: true
  attr :weekdays, :any, required: true
  attr :days_ahead, :any, required: true
  attr :kinds, :any, required: true
  attr :residents, :any, required: true
  attr :groups, :any, required: true
  attr :locations, :any, required: true
  attr :members, :any, required: true
  attr :problems, :any, required: true
  attr :refused_form?, :any, required: true

  def new_routine(assigns) do
    ~H"""
    <details id="new-routine" open={@prescription != nil}>
      <summary>New routine</summary>
      <.routine_form
        button="Start the routine"
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
      />
    </details>
    """
  end

  attr :to, :string, required: true
  attr :label, :string, required: true

  # The link is on one line: a space before its end is drawn with the line
  # under the link.
  def change_link(assigns) do
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
  def routine_form(assigns) do
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
      <.input
        :if={@pattern == "interval"}
        field={@form[:count_from]}
        type="select"
        label="Count the days from"
        options={TaskWords.count_from_options()}
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
      <RescordWeb.TaskComponents.members_field form={@form} name="routine" members={@members} />
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

  def for_words(routine, residents, groups, locations) do
    names =
      names(routine.resident_ids, residents, "A resident who is not here now") ++
        names(routine.group_ids, groups, "A group that is not here now") ++
        names(routine.location_ids, locations, "A location that is not here now")

    if names == [], do: "Nothing in particular", else: Enum.join(names, ", ")
  end

  def names(ids, options, missing) do
    for id <- ids do
      Enum.find_value(options, missing, fn {name, option_id} ->
        if option_id == id, do: String.trim_leading(name, "– ")
      end)
    end
  end

  def who(%{assignee_ids: []}, _members), do: "Anybody"

  def who(%{assignee_ids: ids}, members) do
    ids
    |> Enum.map(fn id ->
      Enum.find_value(members, "A person who is not a member now", fn {email, user_id} ->
        if user_id == id, do: email
      end)
    end)
    |> Enum.join(", ")
  end

  def ended?(%{ends_on: %Date{} = ends_on}, today), do: Date.compare(ends_on, today) == :lt

  def ended?(_routine, _today), do: false

  def state_words(%{paused: true}, _today), do: "Paused"

  def state_words(routine, today) do
    cond do
      ended?(routine, today) -> "Finished"
      Date.compare(routine.starts_on, today) == :gt -> "Not started"
      true -> "Active"
    end
  end

  def state_kind(%{paused: true}, _today), do: "none"

  def state_kind(routine, today) do
    cond do
      ended?(routine, today) -> "none"
      Date.compare(routine.starts_on, today) == :gt -> "info"
      true -> "ok"
    end
  end

  def next_words(instant, organisation) do
    local = Accounts.local_time(organisation, instant)
    "#{ResidentWords.date(DateTime.to_date(local))}, #{TaskWords.time(local)}"
  end

  def edit_path(organisation, routine),
    do: ~p"/o/#{organisation.short_name}/routines/#{routine.id}/edit"
end
