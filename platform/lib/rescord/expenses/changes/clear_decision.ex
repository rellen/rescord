defmodule Rescord.Expenses.Changes.ClearDecision do
  @moduledoc """
  Takes the decision and the payment off an expense that waits for a
  decision again: after a change, or when a person opens the decision again.
  The paper trail keeps what they were.
  """

  use Ash.Resource.Change

  @fields [
    :decided_by_id,
    :decided_at,
    :decline_reason,
    :reimbursed_on,
    :reimbursed_by_id,
    :reimbursement_reference
  ]

  @impl true
  def change(changeset, _opts, _context) do
    Enum.reduce(@fields, changeset, &Ash.Changeset.force_change_attribute(&2, &1, nil))
  end
end
