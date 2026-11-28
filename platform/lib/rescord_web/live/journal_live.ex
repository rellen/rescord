defmodule RescordWeb.JournalLive do
  @moduledoc """
  The journal of one resident, at `/o/<short name>/residents/<id>/journal`.

  The page lists the entries, the newest first, and `?only=medical` gives
  the medical history. A member writes an entry: the form shows the fields
  of the kind that the member chooses. The author of an entry, and an
  administrator, correct it. Each member adds to an entry with an addendum.

  A person who writes an entry attaches files to it: up to five photos or
  PDFs of 20 MB each (ADR 0041). The page writes the entry and its files in
  one transaction, so a refused file writes no entry. Each file links to
  `RescordWeb.AttachmentController`, which reads it with the grants of the
  reader.

  The page shows the conditions of the resident (ADR 0083): `?episode=<id>`
  gives the entries about one condition, with the card of that condition.
  A diagnosis starts a condition, and each other entry can name one.
  `?kind=diagnosis` opens the form of a new entry with that kind.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ConditionComponents
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
         can_track?: Journal.role_can_track?(socket.assigns.role),
         can_episode:
           Map.new(
             [:resolve, :reopen, :revise, :remove],
             &{&1, Journal.role_can_episode?(socket.assigns.role, &1)}
           ),
         today: Accounts.today(socket.assigns.organisation)
       )
       |> allow_files()
       |> assign_episodes()
       |> assign(episode: nil, open_form?: false)
       |> assign_form(%{"kind" => "general"})}
    else
      _no_resident ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such resident.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  # The files of a new entry, for a person who writes one. The page reads
  # the type of each file from its first bytes again (ADR 0041).
  defp allow_files(%{assigns: %{can_write?: true}} = socket) do
    allow_upload(socket, :files,
      accept: ~w(.jpg .jpeg .png .gif .webp .pdf),
      max_entries: 5,
      max_file_size: Journal.max_attachment_size()
    )
  end

  defp allow_files(socket), do: socket

  @impl true
  def handle_params(params, _uri, socket) do
    only = if params["only"] == "medical", do: :medical
    # Only a condition of this resident: the page has them in hand.
    episode = Enum.find(socket.assigns.episodes, &(&1.id == params["episode"]))
    kind = if params["kind"] == "diagnosis", do: "diagnosis", else: "general"

    {:noreply,
     socket
     |> assign(only: only, episode: episode, open_form?: params["kind"] == "diagnosis")
     |> assign_entries()
     |> assign_form(%{"kind" => kind, "episode_id" => (episode && episode.id) || ""})}
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

  # The conditions of the resident, and the same as the options of a form.
  defp assign_episodes(socket) do
    {:ok, episodes} = Journal.episodes_of(socket.assigns.resident.id, options(socket))

    assign(socket,
      episodes: episodes,
      conditions: Enum.map(episodes, &{JournalWords.condition_choice(&1), &1.id})
    )
  end

  defp assign_entries(socket) do
    options = options(socket)
    episode = socket.assigns.episode

    {:ok, entries} =
      Journal.entries(
        socket.assigns.resident.id,
        [only: socket.assigns.only, episode: episode && episode.id] ++ options
      )

    {:ok, prescriptions} = Journal.prescriptions(socket.assigns.resident.id, options)
    {:ok, attachments} = Journal.attachments_of(Enum.map(entries, & &1.id), options)

    assign(socket,
      entries: entries,
      attachments: attachments,
      prescriptions: Enum.map(prescriptions, &{&1.prescription.medication, &1.prescription.id})
    )
  end

  defp assign_form(socket, fields) do
    fields = typed_fields(fields)
    kind = JournalWords.kind_of(fields["kind"]) || :general

    assign(socket,
      form: typed_form(fields, as: :entry),
      kind: kind,
      units: unit_options(socket, fields["measure_kind_id"]),
      joins: joins(socket, kind, fields["condition_id"])
    )
  end

  # The ongoing condition of the resident that a diagnosis of the chosen
  # condition joins, or nil: the form then says so.
  defp joins(socket, :diagnosis, condition_id) when is_binary(condition_id) do
    Enum.find(socket.assigns.episodes, &(&1.condition_id == condition_id and is_nil(&1.ended_on)))
  end

  defp joins(_socket, _kind, _condition_id), do: nil

  @impl true
  def handle_event("choose", %{"entry" => fields}, socket) when is_map(fields) do
    {:noreply, assign_form(socket, fields)}
  end

  def handle_event("write", %{"entry" => fields}, socket) when is_map(fields) do
    with {:ok, instant} <- Accounts.instant(socket.assigns.organisation, fields["at"]),
         facts =
           fields
           |> facts()
           |> Map.merge(%{
             resident_id: socket.assigns.resident.id,
             kind: JournalWords.kind_of(fields["kind"]),
             note: non_blank(fields["note"]),
             happened_at: instant,
             follows_id: non_blank(fields["follows_id"]),
             chronic: fields["chronic"] == "true"
           }),
         {:ok, _entry} <- Journal.write_entry_with_files(facts, files(socket), options(socket)) do
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
        changes =
          fields
          |> facts()
          |> Map.put(:note, non_blank(fields["note"]))
          |> put_about(fields)

        case Journal.correct_entry(entry, changes, options(socket)) do
          {:ok, _entry} -> {:noreply, push_navigate(socket, to: path(socket))}
          {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
        end
    end
  end

  # Starts the condition of a diagnosis from before Rescord recorded the
  # conditions of a resident (ADR 0083).
  def handle_event("track", %{"entry_id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.entries, &(&1.id == id)) do
      nil -> {:noreply, socket}
      entry -> entry |> Journal.track_entry(options(socket)) |> after_episode(socket)
    end
  end

  def handle_event("resolve_episode", %{"episode" => fields}, socket) when is_map(fields) do
    with_episode(socket, fn episode ->
      Journal.resolve_episode(
        episode,
        %{ended_on: non_blank(fields["ended_on"])},
        options(socket)
      )
    end)
  end

  def handle_event("reopen_episode", _params, socket) do
    with_episode(socket, &Journal.reopen_episode(&1, options(socket)))
  end

  def handle_event("revise_episode", %{"episode" => fields}, socket) when is_map(fields) do
    with_episode(socket, fn episode ->
      changes = %{
        started_on: non_blank(fields["started_on"]),
        chronic: fields["chronic"] == "true",
        note: non_blank(fields["note"])
      }

      # The form has the last day only for a condition that is resolved.
      changes =
        if episode.ended_on,
          do: Map.put(changes, :ended_on, non_blank(fields["ended_on"])),
          else: changes

      Journal.revise_episode(episode, changes, options(socket))
    end)
  end

  def handle_event("remove_episode", _params, socket) do
    case socket.assigns.episode do
      nil ->
        {:noreply, socket}

      episode ->
        case Journal.remove_episode(episode, options(socket)) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "The condition is removed.")
             |> push_navigate(to: path(assign(socket, episode: nil)))}

          {:error, error} ->
            {:noreply, assign(socket, problems: Accounts.error_messages(error))}
        end
    end
  end

  def handle_event("cancel_file", %{"ref" => ref}, socket) when is_binary(ref) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("remove_attachment", %{"id" => id}, socket) when is_binary(id) do
    # Only a file of this journal: the page has them in hand.
    with %{} = attachment <-
           socket.assigns.attachments
           |> Map.values()
           |> List.flatten()
           |> Enum.find(&(&1.id == id)),
         :ok <- Journal.remove_attachment(attachment, options(socket)) do
      {:noreply, push_navigate(socket, to: path(socket))}
    else
      nil -> {:noreply, socket}
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs an action on the condition that the page shows.
  defp with_episode(%{assigns: %{episode: nil}} = socket, _action), do: {:noreply, socket}

  defp with_episode(socket, action),
    do: socket.assigns.episode |> action.() |> after_episode(socket)

  defp after_episode(result, socket) do
    case result do
      {:ok, _record} -> {:noreply, push_navigate(socket, to: path(socket))}
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  # The condition that a correction gives an entry, when its form has the
  # field: an empty choice takes the condition off.
  defp put_about(changes, %{"episode_id" => id}), do: Map.put(changes, :episode_id, non_blank(id))
  defp put_about(changes, _fields), do: changes

  # The files that the person chose, each as its name and its bytes.
  defp files(%{assigns: %{uploads: %{files: _}}} = socket) do
    consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
      {:ok, {entry.client_name, File.read!(path)}}
    end)
  end

  defp files(_socket), do: []

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
          amount: "amount",
          episode_id: "episode_id",
          onset_on: "onset_on"
        ],
        value = non_blank(fields[field]),
        not is_nil(value),
        into: %{} do
      {key, value}
    end
  end

  defp path(socket) do
    journal_path(socket.assigns.organisation, socket.assigns.resident.id,
      only: if(socket.assigns.only == :medical, do: "medical"),
      episode: socket.assigns.episode && socket.assigns.episode.id
    )
  end

  defp name(resident), do: resident.name || "a resident with no name"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:residents}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"}>{name(
          @resident
        )}</.link>
      </nav>

      <.header>
        Journal of {name(@resident)}
        <:subtitle>{subtitle(@only, @episode)}, the newest first</:subtitle>
        <:actions>
          <.link
            :if={@only == :medical}
            patch={journal_path(@organisation, @resident.id, episode: @episode && @episode.id)}
            data-variant="secondary"
          >
            Show each kind of entry
          </.link>
          <.link
            :if={@only != :medical}
            patch={
              journal_path(@organisation, @resident.id,
                only: "medical",
                episode: @episode && @episode.id
              )
            }
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

      <.condition_nav
        episodes={@episodes}
        current={@episode}
        only={if @only == :medical, do: "medical"}
        organisation={@organisation}
        resident={@resident}
      />

      <.condition_card :if={@episode} episode={@episode} today={@today} can={@can_episode} />

      <.new_entry
        :if={@can_write?}
        form={@form}
        kind={@kind}
        lists={@lists}
        units={@units}
        prescriptions={@prescriptions}
        uploads={@uploads}
        conditions={@conditions}
        joins={@joins}
        resident={@resident}
        open?={@open_form?}
      />

      <p :if={@entries == [] and is_nil(@episode)}>The journal has no entry yet.</p>
      <p :if={@entries == [] and @episode}>No entry of this kind is about this condition.</p>

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
        attachments={Map.get(@attachments, entry.id, [])}
        conditions={@conditions}
        can_track?={@can_track?}
      />
    </Layouts.app>
    """
  end

  defp subtitle(only, nil),
    do: if(only == :medical, do: "The medical history", else: "Each entry")

  defp subtitle(only, episode) do
    start = if only == :medical, do: "The medical history", else: "The entries"
    "#{start} about #{episode.condition.label}"
  end
end
