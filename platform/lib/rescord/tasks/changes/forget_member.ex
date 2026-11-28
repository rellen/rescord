defmodule Rescord.Tasks.Changes.ForgetMember do
  @moduledoc """
  Takes the user of the argument `user_id` out of the members that a task or
  a routine is for, when that member was taken out of the organisation
  (ADR 0105). A task or a routine left with nobody is for anybody, as one
  with no member always was.

  A task that is done or skipped keeps the person: it says who it was for.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    gone = Ash.Changeset.get_argument(changeset, :user_id)
    named = Ash.Changeset.get_data(changeset, :assignee_ids) || []

    Ash.Changeset.force_change_attribute(changeset, :assignee_ids, List.delete(named, gone))
  end
end
