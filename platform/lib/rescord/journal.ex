defmodule Rescord.Journal do
  @moduledoc """
  The journal of each resident: what the members write about it, with its
  medical history (`docs/domain.md`, section 5.6, and ADR 0030).

  A member writes an entry with `write_entry/2`. The facts of a medical
  kind, such as the value of a measurement, are arguments of that one
  action. `entries/2` gives the journal of a resident with those facts, the
  newest first.

  Each resource here is temporal (ADR 0012), so a correction keeps the entry
  as it was. Pass `as_of:` in the options of a function to read the journal
  as it was at a past instant.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Journal.{EntryKind, Episode, JournalEntry, Series}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Lists, Rescord.Residents, Rescord.Locations]
    # A page reads a series of measurements, which is no resource.
    exports [Rescord.Journal.Series, Rescord.Journal.Series.Point, Rescord.Journal.Standard]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Journal.JournalEntry do
      define :write_entry, action: :write
      define :correct_entry, action: :correct
      define :track_entry, action: :track
      define :entry, action: :read, get_by: [:id], not_found_error?: false
    end

    resource Rescord.Journal.Episode do
      define :episodes, action: :read
      define :episode, action: :read, get_by: [:id], not_found_error?: false
      define :resolve_episode, action: :resolve
      define :reopen_episode, action: :reopen
      define :revise_episode, action: :revise
      define :remove_episode, action: :remove
    end

    resource Rescord.Journal.Diagnosis
    resource Rescord.Journal.Measurement
    resource Rescord.Journal.Procedure
    resource Rescord.Journal.Vaccination
    resource Rescord.Journal.Prescription
    resource Rescord.Journal.Dose

    resource Rescord.Journal.Attachment do
      define :attach_file, action: :attach
      define :attachment, action: :read, get_by: [:id], not_found_error?: false
      define :remove_attachment, action: :remove
    end
  end

  # The facts of each kind that a page shows.
  @facts [
    :vaccination,
    :prescription,
    :follows,
    episode: [condition: [:label]],
    diagnosis: [condition: [:label]],
    measurement: [measure_kind: [:label, standard_unit: [:label]], unit: [:label]],
    procedure: [procedure_kind: [:label]],
    dose: [:prescription]
  ]

  @doc """
  The journal of a resident: its entries with their facts, the newest first
  by the time that each thing happened. `only: :medical` gives the medical
  history, and `episode: id` the entries about one condition of the
  resident (ADR 0083).
  """
  def entries(resident_id, opts \\ []) do
    {only, opts} = Keyword.pop(opts, :only)
    {episode_id, opts} = Keyword.pop(opts, :episode)

    query = Ash.Query.filter(JournalEntry, resident_id == ^resident_id)

    query =
      if episode_id,
        do: Ash.Query.filter(query, episode_id == ^episode_id),
        else: query

    query =
      if only == :medical,
        do: Ash.Query.filter(query, kind in ^EntryKind.medical()),
        else: query

    query
    |> Ash.Query.sort(happened_at: :desc)
    |> Ash.Query.load(@facts)
    |> Ash.read(opts)
  end

  @doc """
  The query that reads the journal of a resident for a page (ADR 0092):
  its entries with their facts and their files, the newest first. A
  collection of a page reads with it, and adds its filters, its search
  and its page.

  `episode: id` gives the entries about one condition of the resident.
  `entry: id` gives one entry, with each entry that adds to it.
  """
  @spec query_to_journal(String.t(), keyword) :: Ash.Query.t()
  def query_to_journal(resident_id, opts \\ []) do
    {episode_id, opts} = Keyword.pop(opts, :episode)
    {entry_id, opts} = Keyword.pop(opts, :entry)

    JournalEntry
    |> Ash.Query.for_read(:read, %{}, opts)
    |> Ash.Query.filter(resident_id == ^resident_id)
    |> about(episode_id)
    |> around(entry_id)
    |> Ash.Query.sort(happened_at: :desc, id: :desc)
    |> Ash.Query.load([:attachments | @facts])
  end

  defp about(query, nil), do: query
  defp about(query, episode_id), do: Ash.Query.filter(query, episode_id == ^episode_id)

  defp around(query, nil), do: query

  defp around(query, entry_id),
    do: Ash.Query.filter(query, id == ^entry_id or follows_id == ^entry_id)

  @doc "Narrows a query of entries to the medical history: the entries of a medical kind."
  @spec medical(Ash.Query.t()) :: Ash.Query.t()
  def medical(%Ash.Query{} = query), do: Ash.Query.filter(query, kind in ^EntryKind.medical())

  @doc """
  Narrows a query of entries to those with the text, in any case of the
  letters: in the note, in the name of a medication or of a vaccine, or in
  the dose of a prescription. It is the search of the journal of a
  resident.
  """
  @spec with_text(Ash.Query.t(), String.t()) :: Ash.Query.t()
  def with_text(%Ash.Query{} = query, text) when is_binary(text) do
    text = Ash.CiString.new(text)

    Ash.Query.filter(
      query,
      contains(note, ^text) or contains(prescription.medication, ^text) or
        contains(prescription.dose, ^text) or contains(vaccination.vaccine, ^text)
    )
  end

  @doc """
  One entry of the journal of a resident, with its facts, or `nil`: when
  there is no such entry, when it is of another resident, and when the
  actor cannot read it. A page that gets the id of an entry from the
  browser finds the entry with this.
  """
  @spec entry_of(String.t(), String.t(), keyword) ::
          {:ok, Ash.Resource.record() | nil} | {:error, term}
  def entry_of(resident_id, entry_id, opts \\ []) do
    JournalEntry
    |> Ash.Query.filter(resident_id == ^resident_id and id == ^entry_id)
    |> Ash.Query.load(@facts)
    |> Ash.read_one(opts)
  end

  @doc """
  One file of the journal of a resident, or `nil`: when there is no such
  file, when its entry is of another resident, and when the actor cannot
  read it.
  """
  @spec attachment_of(String.t(), String.t(), keyword) ::
          {:ok, Ash.Resource.record() | nil} | {:error, term}
  def attachment_of(resident_id, attachment_id, opts \\ []) do
    with {:ok, %{} = attachment} <- attachment(attachment_id, opts),
         {:ok, %{}} <- entry_of(resident_id, attachment.entry_id, opts) do
      {:ok, attachment}
    end
  end

  # The order of two events at one instant: the name of a new resident is
  # before its arrival.
  @order [:name, :arrival, :placement, :group_member, :absence, :departure, :entry, :episode]

  @doc """
  The timeline of a resident (`docs/domain.md`, section 5.6, and ADR 0035):
  its journal entries together with the changes that Rescord recorded, the
  newest first.

  Each event has `subject`, `kind`, `at`, `record` and `user_id`. A journal
  entry has the subject `:entry` and the kind `:written`, at the time that
  the thing happened. Each other event is a change of
  `Rescord.Residents.changes/2` or of `Rescord.Locations.changes/2`, at the
  time that Rescord recorded it.

  An event with the subject `:episode` says that a condition of the
  resident was resolved or was opened again (ADR 0083): its kind is
  `:resolved` or `:reopened`, and it has the name of the condition in
  `condition`. The start of a condition is its diagnosis, which is an entry.
  """
  def timeline(resident_id, opts \\ []) do
    with {:ok, entries} <- entries(resident_id, opts) do
      written =
        for entry <- entries do
          %{
            subject: :entry,
            kind: :written,
            at: entry.happened_at,
            record: entry,
            user_id: entry.author_id
          }
        end

      changes =
        Rescord.Residents.changes(resident_id, opts) ++
          Rescord.Locations.changes(resident_id, opts) ++ episode_changes(resident_id, opts)

      {:ok,
       Enum.sort_by(
         written ++ changes,
         &{DateTime.to_unix(&1.at, :microsecond),
          Enum.find_index(@order, fn s -> s == &1.subject end)},
         :desc
       )}
    end
  end

  # When each condition of a resident was resolved and was opened again,
  # from the versions of its episodes. The policy of the versions refuses
  # each actor (ADR 0063), so the resident decides.
  defp episode_changes(resident_id, opts) do
    with {:ok, %{id: ^resident_id}} <- Rescord.Residents.resident(resident_id, opts),
         {:ok, conditions} <- Rescord.Lists.values(:condition, opts) do
      labels = Map.new(conditions, &{&1.id, to_string(&1.label)})

      Episode
      |> AshPaperTrail.Resource.Info.version_resource()
      |> Ash.Query.filter(resident_id == ^resident_id)
      |> Ash.read!(tenant: opts[:tenant], authorize?: false)
      |> Enum.group_by(& &1.id)
      |> Enum.flat_map(fn {_id, versions} ->
        versions
        |> Enum.sort_by(& &1.valid_at.lower, DateTime)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.flat_map(fn [before, version] ->
          case {before.ended_on, version.ended_on} do
            {nil, %Date{}} -> [episode_change(:resolved, version, labels)]
            {%Date{}, nil} -> [episode_change(:reopened, version, labels)]
            _the_same -> []
          end
        end)
      end)
    else
      _no_resident -> []
    end
  end

  defp episode_change(kind, version, labels) do
    %{
      subject: :episode,
      kind: kind,
      at: version.valid_at.lower,
      record: version,
      user_id: Map.get(version, :user_id),
      condition: Map.get(labels, version.condition_id)
    }
  end

  @doc "One entry with its facts, or `nil` when the actor can read no such entry."
  def entry_with_facts(id, opts \\ []), do: entry(id, Keyword.put(opts, :load, @facts))

  @doc """
  The conditions of a resident (ADR 0083): its episodes, each with the name
  of its condition, its state and the number of its entries. The ongoing
  ones are first, the newest first day first, and then the resolved ones,
  the newest last day first.
  """
  def episodes_of(resident_id, opts \\ []) do
    Episode
    |> Ash.Query.filter(resident_id == ^resident_id)
    |> Ash.Query.load([:state, :entry_count, condition: [:label]])
    |> Ash.read(opts)
    |> case do
      {:ok, episodes} -> {:ok, Enum.sort_by(episodes, &episode_order/1)}
      {:error, error} -> {:error, error}
    end
  end

  defp episode_order(%{ended_on: nil} = episode),
    do: {0, -Date.to_gregorian_days(episode.started_on), episode.id}

  defp episode_order(episode),
    do: {1, -Date.to_gregorian_days(episode.ended_on), episode.id}

  @doc "One condition of a resident, as `episodes_of/2` gives it, or `nil`."
  def episode_with_facts(id, opts \\ []),
    do: episode(id, Keyword.put(opts, :load, [:state, :entry_count, condition: [:label]]))

  @doc """
  What the residents have now (ADR 0083): the ongoing conditions of the
  residents that are in care or away.

  Returns `%{conditions: number, residents: number, by_condition: rows,
  by_location: rows}`. A row of `by_condition` is
  `%{condition: value, count: residents}`, with the value of the list of the
  organisation. A row of `by_location` is `%{location: location, count:
  conditions}`, by where each resident lives now, and the location is `nil`
  for the residents with no place. Each list has the largest number first.
  """
  @spec conditions_now(keyword) :: {:ok, map} | {:error, term}
  def conditions_now(opts \\ []) do
    Episode
    |> Ash.Query.filter(is_nil(ended_on))
    |> Ash.Query.load(condition: [:label], resident: [:status])
    |> Ash.read(opts)
    |> case do
      {:ok, episodes} ->
        current = Enum.filter(episodes, &(&1.resident && &1.resident.status in [:in_care, :away]))
        resident_ids = current |> Enum.map(& &1.resident_id) |> Enum.uniq()

        {:ok,
         %{
           conditions: length(current),
           residents: length(resident_ids),
           by_condition: by_condition(current, & &1.resident_id),
           by_location: by_location(current, resident_ids, opts)
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  # The episodes by condition, with the number of different values of
  # `count_by` in each, the largest number first.
  defp by_condition(episodes, count_by) do
    episodes
    |> Enum.group_by(& &1.condition_id)
    |> Enum.map(fn {_id, [first | _] = of_condition} ->
      %{
        condition: first.condition,
        count: of_condition |> Enum.map(count_by) |> Enum.uniq() |> length()
      }
    end)
    |> Enum.sort_by(&{-&1.count, String.downcase(to_string(&1.condition.label))})
  end

  defp by_location(episodes, resident_ids, opts) do
    homes =
      Map.new(resident_ids, fn resident_id ->
        case Rescord.Locations.home(resident_id, opts) do
          {:ok, [%{location: location} | _]} -> {resident_id, location}
          _no_place -> {resident_id, nil}
        end
      end)

    # Two reads of one location are two records: group by its id.
    episodes
    |> Enum.group_by(fn episode ->
      location = Map.get(homes, episode.resident_id)
      location && location.id
    end)
    |> Enum.map(fn {_id, [first | _] = there} ->
      %{location: Map.get(homes, first.resident_id), count: length(there)}
    end)
    |> Enum.sort_by(&{-&1.count, is_nil(&1.location), &1.location && &1.location.name})
  end

  @doc """
  The conditions that started in each of the last `months` months
  (ADR 0083), by the first day of each, this month included. `condition:
  id` counts one condition only, and `today:` is the date of today in the
  organisation.

  Returns `%{total: number, by_month: rows, by_condition: rows}`. A row of
  `by_month` is `%{month: first_day, count: conditions}`, the newest month
  first, with a row for a month with none. A row of `by_condition` is
  `%{condition: value, count: conditions}`, the largest number first.
  """
  @spec conditions_started(pos_integer, keyword) :: {:ok, map} | {:error, term}
  def conditions_started(months, opts \\ []) when is_integer(months) and months > 0 do
    {condition_id, opts} = Keyword.pop(opts, :condition)

    {today, opts} =
      Keyword.pop_lazy(opts, :today, fn -> Rescord.Accounts.today(opts[:tenant]) end)

    this_month = Date.beginning_of_month(today)
    first = Date.shift(this_month, month: -(months - 1))

    query = Ash.Query.filter(Episode, started_on >= ^first and started_on <= ^today)

    query =
      if condition_id,
        do: Ash.Query.filter(query, condition_id == ^condition_id),
        else: query

    query
    |> Ash.Query.load(condition: [:label])
    |> Ash.read(opts)
    |> case do
      {:ok, episodes} ->
        counts = Enum.frequencies_by(episodes, &Date.beginning_of_month(&1.started_on))

        {:ok,
         %{
           total: length(episodes),
           by_month:
             for back <- 0..(months - 1) do
               month = Date.shift(this_month, month: -back)
               %{month: month, count: Map.get(counts, month, 0)}
             end,
           by_condition: by_condition(episodes, & &1.id)
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  The ongoing episode of a condition that a resident has, or `nil`: the one
  that a new diagnosis of that condition joins.
  """
  def ongoing_episode(resident_id, condition_id, opts \\ []) do
    Episode
    |> Ash.Query.filter(
      resident_id == ^resident_id and condition_id == ^condition_id and is_nil(ended_on)
    )
    |> Ash.Query.sort(started_on: :desc, id: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read(opts)
    |> case do
      {:ok, [episode]} -> {:ok, episode}
      {:ok, []} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Whether a role can run an action of a condition of a resident at all:
  `:resolve`, `:reopen`, `:revise` or `:remove`. A page asks this to decide
  what to show. The policy decides when the action runs.
  """
  @spec role_can_episode?(atom | nil, atom) :: boolean
  def role_can_episode?(role, action)
      when action in [:resolve, :reopen, :revise, :remove],
      do: Rescord.Accounts.granted?(role, Episode, action)

  @doc "Whether a role can start the condition of a diagnosis that has none."
  @spec role_can_track?(atom | nil) :: boolean
  def role_can_track?(role), do: Rescord.Accounts.granted?(role, JournalEntry, :track)

  @doc """
  The newest measurement of each kind for a resident, each as the entry with
  its measurement: the weight of today, for example.
  """
  def latest_measurements(resident_id, opts \\ []) do
    with {:ok, entries} <- entries(resident_id, opts) do
      {:ok,
       entries
       |> Enum.filter(& &1.measurement)
       |> Enum.uniq_by(& &1.measurement.measure_kind_id)
       |> Enum.sort_by(&to_string(&1.measurement.measure_kind.label))}
    end
  end

  @doc """
  The measurements of a resident over time: a series for each measure kind
  that the resident has a measurement of, in the order of the names of the
  kinds (ADR 0080). A chart of the weight draws one of them.
  """
  @spec series(String.t(), keyword) :: {:ok, [Series.t()]} | {:error, term}
  def series(resident_id, opts \\ []) do
    with {:ok, of_each} <- series_of([resident_id], opts) do
      {:ok, Map.get(of_each, resident_id, [])}
    end
  end

  @doc """
  The series of several residents, as a map from the id of each resident to
  its series: the members of a group, for example. A resident with no
  measurement is not a key. This reads the measurements alone, and not the
  rest of the journal.
  """
  @spec series_of([String.t()], keyword) :: {:ok, %{String.t() => [Series.t()]}} | {:error, term}
  def series_of(resident_ids, opts \\ []) do
    JournalEntry
    |> Ash.Query.filter(resident_id in ^resident_ids and kind == :measurement)
    |> Ash.Query.load(
      measurement: [measure_kind: [:label, standard_unit: [:label]], unit: [:label]]
    )
    |> Ash.read(opts)
    |> case do
      {:ok, entries} ->
        {:ok,
         entries
         |> Enum.group_by(& &1.resident_id)
         |> Map.new(fn {resident_id, of_resident} ->
           {resident_id, Series.from_entries(of_resident)}
         end)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  A measurement as a page shows it: in the standard unit of its kind,
  beside what the person recorded (ADR 0094). The measurement has its unit
  and its kind with the standard unit, as `entries/2` and
  `latest_measurements/2` give it.
  """
  @spec standard(map) :: Rescord.Journal.Standard.t()
  def standard(measurement), do: Rescord.Journal.Standard.of(measurement)

  @doc """
  A measurement as a quantity, `1095 g`, or `:error` when it has no unit or
  a unit that Rescord does not know (ADR 0071). The measurement has its
  unit with the label, as `entries/2` and `latest_measurements/2` give it.
  """
  @spec quantity(term) :: {:ok, Rescord.Units.Quantity.t()} | :error
  def quantity(%{value: %Decimal{} = value, unit: unit}) do
    with {:ok, unit} <- Rescord.Lists.known_unit(unit),
         {:ok, quantity} <- Rescord.Units.Quantity.new(value, unit) do
      {:ok, quantity}
    else
      _unknown -> :error
    end
  end

  def quantity(_measurement), do: :error

  @doc """
  The prescriptions of a resident that a dose can name: each as the entry
  with its prescription, the newest first.
  """
  def prescriptions(resident_id, opts \\ []) do
    JournalEntry
    |> Ash.Query.filter(resident_id == ^resident_id and exists(prescription, true))
    |> Ash.Query.sort(happened_at: :desc)
    |> Ash.Query.load(@facts)
    |> Ash.read(opts)
  end

  @doc """
  The journal entry of a prescription, or `nil`. A task that gives a dose
  finds the resident of its prescription with it.
  """
  def entry_of_prescription(prescription_id, opts \\ []) do
    case Ash.get(Rescord.Journal.Prescription, prescription_id, [not_found_error?: false] ++ opts) do
      {:ok, nil} -> {:ok, nil}
      {:ok, prescription} -> entry(prescription.entry_id, opts)
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Writes a journal entry with its files, in one transaction: a refused file
  writes no entry (ADR 0041). `files` is a list of `{name, bytes}`.
  """
  @spec write_entry_with_files(map, [{String.t(), binary}], keyword) ::
          {:ok, Ash.Resource.record()} | {:error, term}
  def write_entry_with_files(facts, files, opts \\ []) do
    # One correlation id for the entry and each of its files (ADR 0100).
    opts = Rescord.Correlation.start(opts)

    Ash.transact(
      [JournalEntry, Rescord.Journal.Attachment],
      fn ->
        with {:ok, entry} <- write_entry(facts, opts),
             :ok <- attach_each(entry, files, opts) do
          {:ok, entry}
        end
      end,
      tenant: opts[:tenant]
    )
    |> case do
      {:ok, {:ok, entry}} -> {:ok, entry}
      {:error, error} -> {:error, error}
    end
  end

  defp attach_each(entry, files, opts) do
    Enum.reduce_while(files, :ok, fn {name, bytes}, :ok ->
      case attach_file(%{entry_id: entry.id, name: name, content: bytes}, opts) do
        {:ok, _attachment} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc """
  The attachments of journal entries, the oldest first, as a map from the id of
  each entry to its attachments. An entry with none is not a key.
  """
  @spec attachments_of([String.t()], keyword) :: {:ok, %{String.t() => [map]}} | {:error, term}
  def attachments_of(entry_ids, opts \\ []) do
    Rescord.Journal.Attachment
    |> Ash.Query.filter(entry_id in ^entry_ids)
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read(opts)
    |> case do
      {:ok, attachments} -> {:ok, Enum.group_by(attachments, & &1.entry_id)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  An attachment and the bytes of its file, when the actor can read the
  attachment and the store has the file. A page that sends the file uses
  this.
  """
  @spec attachment_file(String.t(), keyword) ::
          {:ok, map, binary} | {:error, :not_found | term}
  def attachment_file(id, opts \\ []), do: file_of(id, :key, opts)

  @doc """
  An attachment and the bytes of the thumbnail of its photo, as
  `attachment_file/2` gives the file (ADR 0055). A PDF, and a photo that
  was attached before Rescord made thumbnails, have none.
  """
  @spec attachment_thumbnail(String.t(), keyword) ::
          {:ok, map, binary} | {:error, :not_found | term}
  def attachment_thumbnail(id, opts \\ []), do: file_of(id, :thumbnail_key, opts)

  defp file_of(id, field, opts) do
    with {:ok, %{} = attachment} <- attachment(id, opts),
         key when is_binary(key) <- Map.fetch!(attachment, field),
         {:ok, bytes} <- Rescord.Storage.get(key) do
      {:ok, attachment, bytes}
    else
      {:error, error} -> {:error, error}
      _nothing -> {:error, :not_found}
    end
  end

  @doc """
  Each key of the store that an attachment of the organisation names: the
  file and the thumbnail of each attachment, the removed ones too
  (`Rescord.Storage.Named`, ADR 0091). It reads the table with no actor,
  for `bin/check-files`, and no page calls it.
  """
  @spec file_keys(String.t()) :: [Rescord.Storage.Named.entry()]
  def file_keys(organisation_id),
    do:
      Rescord.Storage.Named.keys(
        Rescord.Journal.Attachment,
        "journal attachment",
        organisation_id
      )

  @doc """
  Whether a role can take a file off an entry: each file with the power
  `:correct_journal`, and the files that the person attached with the power
  `:journal`. A page asks this to decide what to show.
  """
  @spec can_remove_attachment?(term, map, map) :: boolean
  def can_remove_attachment?(:root, _user, _attachment), do: true

  def can_remove_attachment?(role, %{id: user_id}, %{author_id: author_id}) do
    case Rescord.Accounts.Grants.scope(role, Rescord.Journal.Attachment, :remove) do
      {:ok, :all} -> true
      {:ok, :own} -> user_id == author_id
      :none -> false
    end
  end

  @doc "The type of a file from its first bytes, or `nil` for a type that Rescord does not take."
  defdelegate file_type(bytes), to: Rescord.Journal.Changes.StoreAttachment, as: :type_of

  @doc "The largest file of an attachment, in bytes."
  defdelegate max_attachment_size(), to: Rescord.Journal.Changes.StoreAttachment, as: :max_size

  @doc "Whether a kind of entry is a part of the medical history."
  defdelegate medical?(kind), to: EntryKind

  @doc "The arguments that a kind of entry needs, or `nil` for a kind that needs words."
  defdelegate needs(kind), to: Rescord.Journal.Validations.KindHasItsFacts

  @doc "Whether a role can write a journal entry at all."
  @spec role_can_write?(atom | nil) :: boolean
  def role_can_write?(role), do: Rescord.Accounts.granted?(role, JournalEntry, :write)

  @doc """
  Whether a user with a role can correct an entry: its author, an
  administrator, and a root user. A page asks this to decide what to show.
  The policy decides when the action runs.
  """
  @spec can_correct?(term, map, map) :: boolean
  def can_correct?(:root, _user, _entry), do: true

  def can_correct?(role, %{id: user_id}, %{author_id: author_id}) do
    case Rescord.Accounts.Grants.scope(role, JournalEntry, :correct) do
      {:ok, :all} -> true
      {:ok, :own} -> user_id == author_id
      :none -> false
    end
  end
end
