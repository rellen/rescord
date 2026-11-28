defmodule RescordWeb.JournalLive do
  @moduledoc """
  The journal of one resident, at `/o/<short name>/residents/<id>/journal`.

  The entries are a collection (ADR 0092), the newest first, in pages: a
  search in the words of the entries, and a filter on the kind and on the
  date. `?only=medical` is the filter that gives the medical history. The
  address holds the search, the filters and the page (ADR 0084), and
  Cinder reads those parameters. `?entry=<id>` gives one entry, with each
  entry that adds to it: a link from another page to one entry uses it.

  A member writes an entry: the form shows the fields of the kind that
  the member chooses. The author of an entry, and an administrator,
  correct it. Each member adds to an entry with an addendum.

  A person who writes an entry attaches files to it: up to five photos or
  PDFs of 20 MB each (ADR 0041). The page writes the entry and its files in
  one transaction, so a refused file writes no entry. Each file links to
  `RescordWeb.AttachmentController`, which reads it with the grants of the
  reader.

  The page shows the conditions of the resident (ADR 0083): `?episode=<id>`
  gives the entries about one condition, with the card of that condition.
  A diagnosis starts a condition, and each other entry can name one.
  `?new=diagnosis` opens the form of a new entry with that kind.

  The page does not hold the entries: Cinder reads them. An event that
  names an entry or a file by its id reads that record again, as the
  person, and only from the journal of this resident.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  import RescordWeb.ConditionComponents
  import RescordWeb.JournalComponents

  alias Rescord.{Accounts, Journal, Lists, Residents, Tasks}
  alias RescordWeb.JournalWords
  alias RescordWeb.Widgets.Comments

  @lists [:condition, :measure_kind, :procedure_kind, :unit]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)

    with true <- is_binary(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options) do
      {:ok,
       socket
       |> assign(
         resident: resident,
         page_title: "Journal of #{name(resident)}",
         problems: [],
         authors: Accounts.labels(options),
         lists: lists(options),
         measurement_units: RescordWeb.MeasurementUnits.read(options),
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
       |> assign_prescriptions()
       |> assign(episode: nil, entry: nil, query: %{}, open_form?: false)
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
  def handle_params(params, uri, socket) do
    # Only a condition of this resident: the page has them in hand.
    episode = Enum.find(socket.assigns.episodes, &(&1.id == params["episode"]))
    # `?new=<kind>` opens the form with that kind (ADR 0111): `?new=diagnosis`
    # from a condition, and any other kind for a link that names one.
    new =
      Enum.find_value(JournalWords.options(:kind), fn {_word, kind} ->
        kind == params["new"] && kind
      end)

    kind = new || "general"

    {:noreply,
     socket
     |> assign(
       episode: episode,
       entry: one_entry(socket, params["entry"]),
       query: query_of(uri),
       open_form?: new != nil
     )
     |> assign_form(%{"kind" => kind, "episode_id" => (episode && episode.id) || ""})
     |> comments_of()}
  end

  # The one entry has its comments (ADR 0106).
  defp comments_of(socket) do
    case socket.assigns.entry do
      %{id: id} -> Comments.assign_widget(socket, :comments, {:journal_entry, id})
      nil -> socket
    end
  end

  # The one entry that the address names, when it is an entry of this
  # journal that the person can read.
  defp one_entry(socket, id) when is_binary(id), do: entry(socket, id)
  defp one_entry(_socket, _id), do: nil

  # An entry of this journal by its id, as the person, or nil. The id comes
  # from the browser, so a text that is no id gives nil too.
  defp entry(socket, id) do
    case Journal.entry_of(socket.assigns.resident.id, id, options(socket)) do
      {:ok, %{} = entry} -> entry
      _nothing -> nil
    end
  end

  # The parameters of the address, as the browser sent them. The page reads
  # none of the parameters of Cinder: it gives them back in a link, so a
  # person who chooses a condition keeps the search and the filters.
  defp query_of(uri) when is_binary(uri), do: URI.decode_query(URI.parse(uri).query || "")

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp lists(options) do
    for key <- @lists, into: %{} do
      {:ok, values} = Lists.offered_values(key, options)
      {key, Enum.map(values, &{to_string(&1.label), &1.id})}
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

  # The prescriptions of the resident, as the options of the form of a dose.
  defp assign_prescriptions(socket) do
    {:ok, prescriptions} = Journal.prescriptions(socket.assigns.resident.id, options(socket))

    assign(socket,
      prescriptions: Enum.map(prescriptions, &{&1.prescription.medication, &1.prescription.id})
    )
  end

  # The filter that gives the medical history, and the search: Cinder
  # calls each with the query of the entries.
  defp only(query, %{value: "medical"}), do: Journal.medical(query)
  defp only(query, _filter), do: query

  defp search(query, _columns, text), do: Journal.with_text(query, text)

  defp assign_form(socket, fields, error \\ nil) do
    fields = text_fields(fields)
    kind = JournalWords.kind_of(fields["kind"]) || :general
    measure_kind = fields["measure_kind_id"]
    units = socket.assigns.measurement_units
    standard = RescordWeb.MeasurementUnits.standard(units, measure_kind)

    # When the person chooses what was measured, the form chooses the
    # standard unit of that kind (ADR 0094).
    fields =
      if measure_kind != socket.assigns[:measure_kind] and standard,
        do: Map.put(fields, "unit_id", standard),
        else: fields

    assign(socket,
      form: typed_form(fields, as: :entry, error: error),
      kind: kind,
      measure_kind: measure_kind,
      units: RescordWeb.MeasurementUnits.options(units, measure_kind),
      unit_needed?: RescordWeb.MeasurementUnits.needed?(units, measure_kind),
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
      {:noreply,
       socket |> put_flash(:info, "The entry is written.") |> push_navigate(to: here(socket))}
    else
      {:error, error} ->
        {:noreply,
         socket |> assign(problems: Accounts.error_messages(error)) |> assign_form(fields, error)}
    end
  end

  # Plans a task for one dose of a prescription of this journal. A member
  # who completes that task writes the dose to the journal.
  def handle_event("plan_dose", %{"entry_id" => id, "dose" => fields}, socket)
      when is_binary(id) and is_map(fields) do
    with %{prescription: %{}} = entry <- entry(socket, id),
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
       |> push_navigate(to: here(socket))}
    else
      {:error, error} -> {:noreply, assign(socket, problems: Accounts.error_messages(error))}
      # No such prescription in this journal.
      _nothing -> {:noreply, socket}
    end
  end

  def handle_event("correct", %{"entry_id" => id, "entry" => fields}, socket)
      when is_binary(id) and is_map(fields) do
    # Only an entry of this journal.
    case entry(socket, id) do
      nil ->
        {:noreply, socket}

      entry ->
        changes =
          fields
          |> facts()
          |> Map.put(:note, non_blank(fields["note"]))
          |> put_about(fields)

        case Journal.correct_entry(entry, changes, options(socket)) do
          {:ok, _entry} ->
            {:noreply,
             socket
             |> put_flash(:info, "The entry is corrected.")
             |> push_navigate(to: here(socket))}

          {:error, error} ->
            {:noreply, assign(socket, problems: Accounts.error_messages(error))}
        end
    end
  end

  # Starts the condition of a diagnosis from before Rescord recorded the
  # conditions of a resident (ADR 0083).
  def handle_event("track", %{"entry_id" => id}, socket) when is_binary(id) do
    case entry(socket, id) do
      nil ->
        {:noreply, socket}

      entry ->
        entry
        |> Journal.track_entry(options(socket))
        |> after_episode(socket, "The condition is started.")
    end
  end

  def handle_event("resolve_episode", %{"episode" => fields}, socket) when is_map(fields) do
    with_episode(socket, "The condition is resolved.", fn episode ->
      Journal.resolve_episode(
        episode,
        %{ended_on: non_blank(fields["ended_on"])},
        options(socket)
      )
    end)
  end

  def handle_event("reopen_episode", _params, socket) do
    with_episode(
      socket,
      "The condition is open again.",
      &Journal.reopen_episode(&1, options(socket))
    )
  end

  def handle_event("revise_episode", %{"episode" => fields}, socket) when is_map(fields) do
    with_episode(socket, "The condition is saved.", fn episode ->
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
             |> push_navigate(to: here(socket, ["episode"]))}

          {:error, error} ->
            {:noreply, assign(socket, problems: Accounts.error_messages(error))}
        end
    end
  end

  def handle_event("cancel_file", %{"ref" => ref}, socket) when is_binary(ref) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  def handle_event("remove_attachment", %{"id" => id}, socket) when is_binary(id) do
    # Only a file of this journal.
    with {:ok, %{} = attachment} <-
           Journal.attachment_of(socket.assigns.resident.id, id, options(socket)),
         :ok <- Journal.remove_attachment(attachment, options(socket)) do
      {:noreply,
       socket |> put_flash(:info, "The file is taken off.") |> push_navigate(to: here(socket))}
    else
      {:error, %{} = error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}

      _nothing ->
        {:noreply, socket}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Runs an action on the condition that the page shows.
  defp with_episode(%{assigns: %{episode: nil}} = socket, _words, _action),
    do: {:noreply, socket}

  defp with_episode(socket, words, action),
    do: socket.assigns.episode |> action.() |> after_episode(socket, words)

  defp after_episode(result, socket, words) do
    case result do
      {:ok, _record} ->
        {:noreply, socket |> put_flash(:info, words) |> push_navigate(to: here(socket))}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
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

  # The address of the page as it is, with its search, its filters and its
  # page, and with no parameter that opens a form. The page opens again
  # there after a write.
  defp here(socket_or_assigns, without \\ [])
  defp here(%Phoenix.LiveView.Socket{assigns: assigns}, without), do: here(assigns, without)

  defp here(assigns, without) do
    journal_path(
      assigns.organisation,
      assigns.resident.id,
      Map.drop(assigns.query, ["new" | without])
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
      inbox={@inbox}
      ruby={@ruby?}
      section={:residents}
    >
      <.header icon={Icons.section(:journal)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/residents"}>Residents</:crumb>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"}>
          {name(@resident)}
        </:crumb>
        Journal of {name(@resident)}
        <:subtitle>{subtitle(@episode)}, the newest first</:subtitle>
        <:actions>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/timeline"}
            data-variant="secondary"
          >
            <.icon name="timeline" /> Timeline
          </.link>
        </:actions>
      </.header>

      <.problems list={@problems} />

      <.condition_nav
        episodes={@episodes}
        current={@episode}
        query={@query}
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
        unit_needed?={@unit_needed?}
        prescriptions={@prescriptions}
        uploads={@uploads}
        conditions={@conditions}
        joins={@joins}
        resident={@resident}
        open?={@open_form?}
      />

      <p :if={@entry} id="one-entry">
        This is one entry of the journal, with what a member added to it.
        <.link patch={here(assigns, ["entry", "page"])}>Show each entry</.link>
      </p>

      <section id="entries" aria-label="Entries">
        <Cinder.collection
          id="journal"
          layout={:list}
          query={
            Journal.query_to_journal(@resident.id,
              episode: @episode && @episode.id,
              entry: @entry && @entry.id,
              actor: @current_user,
              tenant: @organisation
            )
          }
          actor={@current_user}
          tenant={@organisation}
          url_state={@url_state}
          page_size={[default: 25, options: [25, 50, 100]]}
          show_sort={false}
          search={[
            label: "Search",
            placeholder: "A word of an entry",
            fn: &search/3
          ]}
        >
          <:col field="note" search />
          <:filter
            field="only"
            type="select"
            label="Show"
            prompt="Each kind of entry"
            options={[{"The medical history", "medical"}]}
            fn={&only/2}
          />
          <:filter
            field="kind"
            type="select"
            label="Kind"
            prompt="Any kind"
            options={JournalWords.options(:kind)}
          />
          <:filter field="happened_at" type="date_range" label="Date" />
          <:empty :let={found}>
            <p :if={found.filtered?}>No entry matches the search and the filters.</p>
            <p :if={not found.filtered? and is_nil(@episode)}>The journal has no entry yet.</p>
            <p :if={not found.filtered? and @episode}>No entry is about this condition.</p>
          </:empty>
          <:item :let={entry}>
            <.entry_card
              entry={entry}
              organisation={@organisation}
              authors={@authors}
              current_user={@current_user}
              role={@role}
              can_plan?={@can_plan?}
              can_start_routine?={@can_start_routine?}
              today={@today}
              can_write?={@can_write?}
              attachments={entry.attachments}
              conditions={@conditions}
              can_track?={@can_track?}
              comments_link?={is_nil(@entry)}
            />
          </:item>
        </Cinder.collection>
      </section>

      <Comments.render :if={@entry} state={@comments} record="this entry" />
    </Layouts.app>
    """
  end

  defp subtitle(nil), do: "Each entry"
  defp subtitle(episode), do: "The entries about #{episode.condition.label}"
end
