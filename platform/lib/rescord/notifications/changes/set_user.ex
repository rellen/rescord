defmodule Rescord.Notifications.Changes.SetUser do
  @moduledoc """
  Makes the actor the person of a new device, topic or preference. With no
  user, the change does nothing, and the policy refuses the action.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, %{actor: %Rescord.Accounts.User{id: id}}),
    do: Ash.Changeset.force_change_attribute(changeset, :user_id, id)

  def change(changeset, _opts, _context), do: changeset
end
