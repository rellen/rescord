defmodule Rescord.Tasks.Changes.TakeTask do
  @moduledoc """
  Makes the actor the member that a task is for. With no user the change
  does nothing, and the policy refuses the action.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %Rescord.Accounts.User{id: id}}),
    do: Ash.Changeset.force_change_attribute(changeset, :assignee_id, id)

  def change(changeset, _opts, _context), do: changeset
end
