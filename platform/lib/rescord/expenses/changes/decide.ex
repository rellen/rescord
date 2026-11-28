defmodule Rescord.Expenses.Changes.Decide do
  @moduledoc """
  Records who decided an expense, and when: the actor, at the time of the
  action. An approval keeps no reason of an earlier refusal.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    by = if match?(%Rescord.Accounts.User{}, context.actor), do: context.actor.id

    changeset
    |> Ash.Changeset.force_change_attribute(:decided_by_id, by)
    |> Ash.Changeset.force_change_attribute(:decided_at, DateTime.utc_now())
    |> then(fn changeset ->
      if changeset.action.name == :approve,
        do: Ash.Changeset.force_change_attribute(changeset, :decline_reason, nil),
        else: changeset
    end)
  end
end
