defmodule Rescord.Journal.Validations.EntryOfOrganisation do
  @moduledoc """
  An attachment names a journal entry of the organisation, and one that the
  actor can read. The validation runs after the policy, so a person with no
  grant gets the answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Journal.JournalEntry

  @impl true
  def validate(changeset, _opts, context) do
    with entry_id when is_binary(entry_id) <- Ash.Changeset.get_attribute(changeset, :entry_id),
         {:ok, %JournalEntry{}} <-
           JournalEntry
           |> Ash.Query.filter(id == ^entry_id)
           |> Ash.read_one(tenant: changeset.tenant, actor: context.actor) do
      :ok
    else
      _no_entry -> {:error, field: :entry_id, message: "is not an entry of this journal"}
    end
  end
end
