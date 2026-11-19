defmodule Rescord.Transfers.Changes.Answer do
  @moduledoc "Records who answered a partnership or a transfer, and when: the actor, now."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    by = if match?(%Rescord.Accounts.User{}, context.actor), do: context.actor.id

    changeset
    |> Ash.Changeset.force_change_attribute(:answered_by_id, by)
    |> Ash.Changeset.force_change_attribute(:answered_at, DateTime.utc_now())
  end
end
