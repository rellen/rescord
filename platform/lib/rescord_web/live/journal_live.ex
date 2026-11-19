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

  import RescordWeb.JournalComponents

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
         units_of: units_of(options),
         can_write?: Journal.role_can_write?(socket.assigns.role),
         can_plan?: Tasks.role_can?(socket.assigns.role, :plan),
         can_start_routine?: Tasks.role_can_routine?(socket.assigns.role, :start),
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

  # The units of each measure kind that names some: a map from the id of
  # the kind to the ids of its units.
  defp units_of(options) do
    {:ok, kinds} = Lists.values(:measure_kind, options)
    for kind <- kinds, kind.unit_ids != [], into: %{}, do: {kind.id, kind.unit_ids}
  end

  # The units that the form of a measurement offers: those of the chosen
  # kind, or each unit when the kind names none.
  defp unit_options(socket, kind_id) do
    all = socket.assigns.lists.unit

    case Map.get(socket.assigns.units_of, kind_id) do
      nil -> all
      ids -> Enum.filter(all, fn {_label, id} -> id in ids end)
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
    fields = typed_fields(fields)

    assign(socket,
      form: typed_form(fields, as: :entry),
      kind: JournalWords.kind_of(fields["kind"]) || :general,
      units: unit_options(socket, fields["measure_kind_id"])
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
             note: non_blank(fields["note"]),
             happened_at: instant,
             follows_id: non_blank(fields["follows_id"])
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
        changes = Map.put(facts(fields), :note, non_blank(fields["note"]))

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
        value = non_blank(fields[field]),
        not is_nil(value),
        into: %{} do
      {key, value}
    end
  end

  defp path(socket) do
    base =
      ~p"/o/#{socket.assigns.organisation.short_name}/residents/#{socket.assigns.resident.id}/journal"

    if socket.assigns.only == :medical, do: base <> "?only=medical", else: base
  end

  defp name(resident), do: resident.name || "a resident with no name"

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

      <.new_entry
        :if={@can_write?}
        form={@form}
        kind={@kind}
        lists={@lists}
        units={@units}
        prescriptions={@prescriptions}
      />

      <p :if={@entries == []}>The journal has no entry yet.</p>

      <.entry_card
        :for={entry <- @entries}
        entry={entry}
        organisation={@organisation}
        authors={@authors}
        current_user={@current_user}
        role={@role}
        can_plan?={@can_plan?}
        can_start_routine?={@can_start_routine?}
        today={@today}
        can_write?={@can_write?}
      />
    </Layouts.app>
    """
  end
end
