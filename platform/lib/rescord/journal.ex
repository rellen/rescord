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
    deps [Rescord, Rescord.Accounts, Rescord.Lists, Rescord.Residents]
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
  @spec can_correct?(atom | nil, map, map) :: boolean
  def can_correct?(role, _user, _entry) when role in [:root, :administrator], do: true
  def can_correct?(:member, %{id: user_id}, %{author_id: author_id}), do: user_id == author_id
  def can_correct?(_role, _user, _entry), do: false
end
