defmodule Rescord.Usage.Changes.SendingSince do
  @moduledoc """
  Writes the day that a root user turned the mode `send` on, in UTC. No day
  before it is ever sent (ADR 0098). A change to another mode leaves it, and
  a change back to `send` writes the new day, so that the days in between,
  when the root user wanted nothing sent, stay on the server.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    turned_on? =
      Ash.Changeset.get_attribute(changeset, :mode) == :send and
        changeset.data.mode != :send

    if turned_on?,
      do: Ash.Changeset.force_change_attribute(changeset, :sending_since, Date.utc_today()),
      else: changeset
  end
end
