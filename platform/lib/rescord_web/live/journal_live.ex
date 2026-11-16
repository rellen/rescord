defmodule RescordWeb.JournalLive do
  @moduledoc """
  The journal of one resident, at `/o/<short name>/residents/<id>/journal`.

  The page lists the entries, the newest first, and `?only=medical` gives
  the medical history. A member writes an entry: the form shows the fields
  of the kind that the member chooses. The author of an entry, and an
  administrator, correct it. Each member adds to an entry with an addendum.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Journal, Lists, Residents, Tasks}
  alias RescordWeb.JournalWords

  @lists [:condition, :measure_kind, :procedure_kind, :unit]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)

    with true <- is_binary(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options) do
      {:ok, members} = Accounts.members([load: [:email]] ++ options)

      {:ok,
       socket
       |> assign(
         resident: resident,
         page_title: "Journal of #{name(resident)}",
         problems: [],
         authors: Map.new(members, &{&1.user_id, to_string(&1.email)}),
         lists: lists(options),
         can_write?: Journal.role_can_write?(socket.assigns.role),
         can_plan?: Tasks.role_can?(socket.assigns.role, :plan),
         today: Accounts.today(socket.assigns.organisation)
       )
       |> assign_form(%{"kind" => "general"})}
    else
      _no_resident ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such resident.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    only = if params["only"] == "medical", do: :medical
    {:noreply, socket |> assign(only: only) |> assign_entries()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp lists(options) do
    for key <- @lists, into: %{} do
      {:ok, values} = Lists.offered_values(key, options)
      {key, Enum.map(values, &{to_string(&1.label), &1.id})}
    end
  end

  defp assign_entries(socket) do
    options = options(socket)

    {:ok, entries} =
      Journal.entries(socket.assigns.resident.id, [only: socket.assigns.only] ++ options)

    {:ok, prescriptions} = Journal.prescriptions(socket.assigns.resident.id, options)

    assign(socket,
      entries: entries,
      prescriptions: Enum.map(prescriptions, &{&1.prescription.medication, &1.prescription.id})
    )
  end

  defp assign_form(socket, fields) do
    assign(socket,
      form: to_form(fields, as: :entry),
      kind: JournalWords.kind_of(fields["kind"]) || :general
    )
  end

  @impl true
  def handle_event("choose", %{"entry" => fields}, socket) when is_map(fields) do
    {:noreply, assign_form(socket, fields)}
  end

  def handle_event("write", %{"entry" => fields}, socket) when is_map(fields) do
    with {:ok, instant} <- Accounts.instant(socket.assigns.organisation, fields["at"]),
         {:ok, _entry} <-
           fields
           |> facts()
           |> Map.merge(%{
             resident_id: socket.assigns.resident.id,
             kind: JournalWords.kind_of(fields["kind"]),
             note: text(fields["note"]),
             happened_at: instant,
             follows_id: text(fields["follows_id"])
           })
           |> Journal.write_entry(options(socket)) do
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      {:error, words} when is_binary(words) ->
        {:noreply, socket |> assign(problems: [words]) |> assign_form(fields)}

      {:error, error} ->
        {:noreply,
         socket |> assign(problems: Accounts.error_messages(error)) |> assign_form(fields)}
    end
  end

  # Plans a task for one dose of a prescription of this journal. A member
  # who completes that task writes the dose to the journal.
  def handle_event("plan_dose", %{"entry_id" => id, "dose" => fields}, socket)
      when is_binary(id) and is_map(fields) do
    entry = Enum.find(socket.assigns.entries, &(&1.id == id and &1.prescription))

    with %{} <- entry,
         {:ok, due_at} <-
           Accounts.local_instant(
             socket.assigns.organisation,
             "#{fields["date"]}T#{fields["time"]}"
           ),
         {:ok, _task} <-
           Tasks.plan_task(
             %{
               title: "Medicate: #{entry.prescription.medication}",
               note: entry.prescription.dose,
               due_at: due_at,
               prescription_id: entry.prescription.id,
               resident_ids: [socket.assigns.resident.id]
             },
             options(socket)
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "The dose is in the tasks of that day.")
       |> push_navigate(to: path(socket))}
    else
      nil -> {:noreply, socket}
      {:error, words} when is_binary(words) -> {:noreply, assign(socket, problems: [words])}
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event("correct", %{"entry_id" => id, "entry" => fields}, socket)
      when is_binary(id) and is_map(fields) do
    # Only an entry of this journal: the page has them in hand.
    case Enum.find(socket.assigns.entries, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      entry ->
        changes = Map.put(facts(fields), :note, text(fields["note"]))

        case Journal.correct_entry(entry, changes, options(socket)) do
          {:ok, _entry} -> {:noreply, push_navigate(socket, to: path(socket))}
          {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
        end
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The facts of a medical kind that a form can send. A field that is empty
  # is not given, so it changes nothing.
  defp facts(fields) do
    for {key, field} <- [
          condition_id: "condition_id",
          measure_kind_id: "measure_kind_id",
          value: "value",
          unit_id: "unit_id",
          procedure_kind_id: "procedure_kind_id",
          vaccine: "vaccine",
          medication: "medication",
          dose: "dose",
          route: "route",
          starts_on: "starts_on",
          ends_on: "ends_on",
          prescription_id: "prescription_id",
          amount: "amount"
        ],
        value = text(fields[field]),
        not is_nil(value),
        into: %{} do
      {key, value}
    end
  end

  defp text(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: value)
  defp text(_other), do: nil

  defp path(socket) do
    base =
      ~p"/o/#{socket.assigns.organisation.short_name}/residents/#{socket.assigns.resident.id}/journal"

    if socket.assigns.only == :medical, do: base <> "?only=medical", else: base
  end

  defp name(resident), do: resident.name || "a resident with no name"

  # The address of the author, when the author is a member. A root user is
  # not a member, and reads their own entries as their own.
  defp author(authors, entry, user) do
    cond do
      Map.has_key?(authors, entry.author_id) -> authors[entry.author_id]
      entry.author_id == user.id -> to_string(user.email)
      true -> "a person who is not a member now"
    end
  end

  defp when_words(organisation, instant),
    do: JournalWords.time(Accounts.local_time(organisation, instant))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"}>{name(
          @resident
        )}</.link>
      </nav>

      <.header>
        Journal of {name(@resident)}
        <:subtitle>
          {if @only == :medical, do: "The medical history", else: "Each entry"}, the newest first
        </:subtitle>
        <:actions>
          <.link
            :if={@only == :medical}
            patch={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/journal"}
            data-variant="secondary"
          >
            Show each entry
          </.link>
          <.link
            :if={@only != :medical}
            patch={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/journal?only=medical"}
            data-variant="secondary"
          >
            Show the medical history
          </.link>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/timeline"}
            data-variant="secondary"
          >
            Timeline
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <details :if={@can_write?} id="new-entry">
        <summary>New journal entry</summary>
        <.form for={@form} id="entry" phx-change="choose" phx-submit="write">
          <.input
            field={@form[:kind]}
            type="select"
            label="Kind"
            options={JournalWords.options(:kind)}
          />
          <.input
            :if={@kind == :diagnosis}
            field={@form[:condition_id]}
            type="select"
            label="Condition"
            prompt="Choose"
            options={@lists.condition}
            required
          />
          <.input
            :if={@kind == :measurement}
            field={@form[:measure_kind_id]}
            type="select"
            label="What was measured"
            prompt="Choose"
            options={@lists.measure_kind}
            required
          />
          <.input
            :if={@kind == :measurement}
            field={@form[:value]}
            type="number"
            step="any"
            label="Value"
            required
          />
          <.input
            :if={@kind == :measurement}
            field={@form[:unit_id]}
            type="select"
            label="Unit"
            prompt="No unit"
            options={@lists.unit}
          />
          <.input
            :if={@kind == :procedure}
            field={@form[:procedure_kind_id]}
            type="select"
            label="Procedure"
            prompt="Choose"
            options={@lists.procedure_kind}
            required
          />
          <.input
            :if={@kind == :vaccination}
            field={@form[:vaccine]}
            type="text"
            label="Vaccine"
            maxlength="120"
            required
          />
          <.input
            :if={@kind == :prescription}
            field={@form[:medication]}
            type="text"
            label="Medication"
            maxlength="120"
            required
          />
          <.input
            :if={@kind == :prescription}
            field={@form[:dose]}
            type="text"
            label="How much and how often"
            maxlength="200"
          />
          <.input
            :if={@kind == :prescription}
            field={@form[:route]}
            type="select"
            label="Route"
            prompt="Not recorded"
            options={JournalWords.options(:route)}
          />
          <.input
            :if={@kind == :prescription}
            field={@form[:starts_on]}
            type="date"
            label="First day"
          />
          <.input :if={@kind == :prescription} field={@form[:ends_on]} type="date" label="Last day" />
          <.input
            :if={@kind == :dose and @prescriptions != []}
            field={@form[:prescription_id]}
            type="select"
            label="Of the prescription"
            prompt="No prescription"
            options={@prescriptions}
          />
          <.input
            :if={@kind == :dose}
            field={@form[:amount]}
            type="text"
            label="How much"
            maxlength="120"
          />
          <.input
            field={@form[:note]}
            type="textarea"
            label={if Journal.needs(@kind), do: "Note", else: "What happened"}
            maxlength="2000"
            required={is_nil(Journal.needs(@kind))}
          />
          <.input field={@form[:at]} type="datetime-local" label="When it happened, if not now" />
          <footer><.button type="submit">Write the entry</.button></footer>
        </.form>
      </details>

      <p :if={@entries == []}>The journal has no entry yet.</p>

      <article :for={entry <- @entries} id={"entry-#{entry.id}"}>
        <header>
          <strong>{JournalWords.kind(entry.kind)}</strong>
          <small>
            <time datetime={DateTime.to_iso8601(entry.happened_at)}>
              {when_words(@organisation, entry.happened_at)}
            </time>
            · {author(@authors, entry, @current_user)}
          </small>
        </header>
        <p :if={entry.follows}>
          Adds to the entry of {when_words(@organisation, entry.follows.happened_at)}.
        </p>
        <p :if={JournalWords.facts(entry)}>{JournalWords.facts(entry)}</p>
        <p :if={entry.note}>{entry.note}</p>

        <details
          :if={Journal.can_correct?(@role, @current_user, entry)}
          id={"correct-details-#{entry.id}"}
        >
          <summary>Correct this entry</summary>
          <p>Correct a mistake only. The history keeps the entry as it was.</p>
          <form id={"correct-#{entry.id}"} phx-submit="correct">
            <input type="hidden" name="entry_id" value={entry.id} />
            <.input
              :if={entry.measurement}
              id={"correct-#{entry.id}-value"}
              name="entry[value]"
              type="number"
              step="any"
              label="Value"
              value={JournalWords.number(entry.measurement.value) |> String.replace(",", "")}
            />
            <.input
              id={"correct-#{entry.id}-note"}
              name="entry[note]"
              type="textarea"
              label="Note"
              value={entry.note}
              maxlength="2000"
            />
            <footer><.button type="submit">Save the correction</.button></footer>
          </form>
        </details>

        <details :if={entry.prescription && @can_plan?} id={"dose-details-#{entry.id}"}>
          <summary>Plan a dose</summary>
          <p>The dose is a task. The member who completes it writes the dose to this journal.</p>
          <form id={"plan-dose-#{entry.id}"} phx-submit="plan_dose">
            <input type="hidden" name="entry_id" value={entry.id} />
            <.input
              id={"plan-dose-#{entry.id}-date"}
              name="dose[date]"
              type="date"
              label="Day"
              value={Date.to_iso8601(@today)}
              required
            />
            <.input
              id={"plan-dose-#{entry.id}-time"}
              name="dose[time]"
              type="time"
              label="Time"
              value="08:00"
              required
            />
            <footer><.button type="submit">Plan the dose</.button></footer>
          </form>
          <p>
            <.link navigate={
              ~p"/o/#{@organisation.short_name}/routines?prescription=#{entry.prescription.id}"
            }>Plan the doses as a routine</.link>
          </p>
        </details>

        <details :if={@can_write?} id={"add-details-#{entry.id}"}>
          <summary>Add to this entry</summary>
          <form id={"add-#{entry.id}"} phx-submit="write">
            <input type="hidden" name="entry[kind]" value={entry.kind} />
            <input type="hidden" name="entry[follows_id]" value={entry.id} />
            <.input
              id={"add-#{entry.id}-note"}
              name="entry[note]"
              type="textarea"
              label="What to add"
              value=""
              maxlength="2000"
              required
            />
            <footer><.button type="submit">Add to the entry</.button></footer>
          </form>
        </details>
      </article>
    </Layouts.app>
    """
  end
end
