defmodule Rescord.Tasks.Changes.TakeTask do
  @moduledoc """
  Adds the actor to the members that a task is for. The other members stay.
  With no user the change does nothing, and the policy refuses the action.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %Rescord.Accounts.User{id: id}}) do
    members = Ash.Changeset.get_attribute(changeset, :assignee_ids) || []

    Ash.Changeset.force_change_attribute(changeset, :assignee_ids, Enum.uniq(members ++ [id]))
  end

  def change(changeset, _opts, _context), do: changeset
end
