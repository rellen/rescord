defmodule Rescord.Expenses.Changes.TakeOffReceipts do
  @moduledoc """
  Takes the receipts off an expense that a person withdraws, in the same
  transaction (ADR 0036): a removal reaches what names the record. The
  files stay in the store, as for each receipt that a person takes off.

  The person can withdraw the expense, which the policy of `withdraw`
  decided, so the receipts go with it for each role: this reads and
  archives them with no policy.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Expenses.Receipt

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      options = [
        tenant: changeset.tenant,
        context: Map.take(changeset.context, [:shared]),
        actor: context.actor,
        authorize?: false
      ]

      Receipt
      |> Ash.Query.filter(expense_id == ^changeset.data.id)
      |> Ash.read!(options)
      |> Enum.each(&Ash.destroy!(&1, [action: :discard] ++ options))

      changeset
    end)
  end
end
