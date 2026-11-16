defmodule Rescord.Journal.Validations.SameResident do
  @moduledoc """
  An entry is about one resident, and what it names is about the same one:

    * an addendum follows an entry of its own resident;
    * a dose names a prescription of its own resident.

  Without this rule an entry in the journal of one resident could add to
  the entry of another, or record a dose of the medication of another.

  The validation runs after the policy, so a person who cannot write the
  entry gets the answer of the policy.
  """

  use Ash.Resource.Validation

  alias Rescord.Journal.{JournalEntry, Prescription}

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    resident_id = Ash.Changeset.get_attribute(changeset, :resident_id)
    options = options(changeset)

    cond do
      not same?(follows(changeset, options), resident_id) ->
        {:error, field: :follows_id, message: "is an entry about another resident"}

      not same?(prescribed(changeset, options), resident_id) ->
        {:error, field: :prescription_id, message: "is a prescription for another resident"}

      true ->
        :ok
    end
  end

  # `:none` is nothing to compare: the action names no such record.
  defp same?(:none, _resident_id), do: true
  defp same?(other, resident_id), do: other == resident_id

  # The resident of the entry that the new entry follows.
  defp follows(changeset, options) do
    case Ash.Changeset.get_attribute(changeset, :follows_id) do
      nil -> :none
      id -> resident_of_entry(id, options)
    end
  end

  # The resident of the prescription that a dose names.
  defp prescribed(changeset, options) do
    with {:ok, id} when is_binary(id) <- Ash.Changeset.fetch_argument(changeset, :prescription_id),
         %Prescription{entry_id: entry_id} <-
           Ash.get!(Prescription, id, [not_found_error?: false] ++ options) do
      resident_of_entry(entry_id, options)
    else
      {:ok, nil} -> :none
      :error -> :none
      # A prescription that is not there: the database refuses the dose.
      nil -> :none
    end
  end

  defp resident_of_entry(id, options) do
    case Ash.get!(JournalEntry, id, [not_found_error?: false] ++ options) do
      nil -> nil
      entry -> entry.resident_id
    end
  end

  defp options(changeset) do
    base = [tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
