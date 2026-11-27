defmodule Rescord.Tasks.Changes.ForgetResident do
  @moduledoc """
  Takes the resident of the argument `resident_id` out of the residents that
  a routine names (ADR 0067). The tasks that the routine makes after this
  do not name that resident.

  The tasks that exist keep their time and their state: the listener of
  `Rescord.Tasks.TaskSubject` takes the resident out of them.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    gone = Ash.Changeset.get_argument(changeset, :resident_id)
    named = Ash.Changeset.get_data(changeset, :resident_ids) || []

    Ash.Changeset.force_change_attribute(changeset, :resident_ids, List.delete(named, gone))
  end
end
