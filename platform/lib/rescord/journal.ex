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

  alias Rescord.Journal.{EntryKind, JournalEntry}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Lists, Rescord.Residents, Rescord.Locations]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Journal.JournalEntry do
      define :write_entry, action: :write
      define :correct_entry, action: :correct
      define :entry, action: :read, get_by: [:id], not_found_error?: false
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
    diagnosis: [condition: [:label]],
    measurement: [measure_kind: [:label], unit: [:label]],
    procedure: [procedure_kind: [:label]],
    dose: [:prescription]
  ]

  @doc """
  The journal of a resident: its entries with their facts, the newest first
  by the time that each thing happened. `only: :medical` gives the medical
  history.
  """
  def entries(resident_id, opts \\ []) do
    {only, opts} = Keyword.pop(opts, :only)

    query = Ash.Query.filter(JournalEntry, resident_id == ^resident_id)

    query =
      if only == :medical,
        do: Ash.Query.filter(query, kind in ^EntryKind.medical()),
        else: query

    query
    |> Ash.Query.sort(happened_at: :desc)
    |> Ash.Query.load(@facts)
    |> Ash.read(opts)
  end

  # The order of two events at one instant: the name of a new resident is
  # before its arrival.
  @order [:name, :arrival, :placement, :group_member, :absence, :departure, :entry]

  @doc """
  The timeline of a resident (`docs/domain.md`, section 5.6, and ADR 0035):
  its journal entries together with the changes that Rescord recorded, the
  newest first.

  Each event has `subject`, `kind`, `at`, `record` and `user_id`. A journal
  entry has the subject `:entry` and the kind `:written`, at the time that
  the thing happened. Each other event is a change of
  `Rescord.Residents.changes/2` or of `Rescord.Locations.changes/2`, at the
  time that Rescord recorded it.
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
          Rescord.Locations.changes(resident_id, opts)

      {:ok,
       Enum.sort_by(
         written ++ changes,
         &{DateTime.to_unix(&1.at, :microsecond),
          Enum.find_index(@order, fn s -> s == &1.subject end)},
         :desc
       )}
    end
  end

  @doc "One entry with its facts, or `nil` when the actor can read no such entry."
  def entry_with_facts(id, opts \\ []), do: entry(id, Keyword.put(opts, :load, @facts))

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
  The prescriptions of a resident that a dose can name: each as the entry
  with its prescription, the newest first.
  """
  def prescriptions(resident_id, opts \\ []) do
    with {:ok, entries} <- entries(resident_id, opts) do
      {:ok, Enum.filter(entries, & &1.prescription)}
    end
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
