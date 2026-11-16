defmodule Rescord.Tasks.Changes.Finish do
  @moduledoc """
  Records who finished a task, and when: the actor, at the time of the
  action. A task that is done and a task that is skipped are both finished.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    by = if match?(%Rescord.Accounts.User{}, context.actor), do: context.actor.id

    changeset
    |> Ash.Changeset.force_change_attribute(:finished_at, DateTime.utc_now())
    |> Ash.Changeset.force_change_attribute(:finished_by_id, by)
  end
end
