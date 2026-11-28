defmodule Rescord.Accounts.Changes.SetAuthor do
  @moduledoc """
  Makes the actor the author of a new record: it writes the id of the user
  in the attribute `author_id`. Each domain with records that a person
  writes uses this one change (ADR 0086).

  With no user, the change does nothing. The policy then refuses the action,
  as it refuses each action of a person who is not signed in: an error from
  here would give that person another answer than `forbidden`.
  """

  use Ash.Resource.Change

  # The change reads the actor only.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, %{actor: %Rescord.Accounts.User{id: id}}) do
    Ash.Changeset.force_change_attribute(changeset, :author_id, id)
  end

  def change(changeset, _opts, _context), do: changeset
end
