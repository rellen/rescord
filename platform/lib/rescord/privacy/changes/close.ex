defmodule Rescord.Privacy.Changes.Close do
  @moduledoc """
  Closes a request (ADR 0105): it says when, and the contact of the person
  goes. The rest of the request stays, as the proof of what was done.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(:closed_at, DateTime.utc_now())
    |> Ash.Changeset.force_change_attribute(:encrypted_contact, nil)
  end
end
