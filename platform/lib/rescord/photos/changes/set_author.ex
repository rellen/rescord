defmodule Rescord.Photos.Changes.SetAuthor do
  @moduledoc """
  Makes the actor the author of a new photo.

  With no user, the change does nothing. The policy then refuses the action,
  as it refuses each action of a person who is not signed in: an error from
  here would give that person another answer than `forbidden`.
  """

  use Ash.Resource.Change

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, %{actor: %Rescord.Accounts.User{id: id}}) do
    Ash.Changeset.force_change_attribute(changeset, :author_id, id)
  end

  def change(changeset, _opts, _context), do: changeset
end
