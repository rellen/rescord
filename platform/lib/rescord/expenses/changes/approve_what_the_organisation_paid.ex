defmodule Rescord.Expenses.Changes.ApproveWhatTheOrganisationPaid do
  @moduledoc """
  Approves at once a new expense that the organisation paid (ADR 0082).

  Only `record` has this change, and only a person who manages the expenses
  runs `record`: that person would approve their own record a moment later.
  An expense that a member paid still waits for a decision, so that a
  person decides each payment to a member in an action of its own.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    case Ash.Changeset.get_attribute(changeset, :paid_by) do
      :organisation ->
        by = if match?(%Rescord.Accounts.User{}, context.actor), do: context.actor.id

        changeset
        |> Ash.Changeset.force_change_attribute(:state, :approved)
        |> Ash.Changeset.force_change_attribute(:decided_by_id, by)
        |> Ash.Changeset.force_change_attribute(:decided_at, DateTime.utc_now())

      _a_member ->
        changeset
    end
  end
end
