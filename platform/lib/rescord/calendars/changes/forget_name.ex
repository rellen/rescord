defmodule Rescord.Calendars.Changes.ForgetName do
  @moduledoc """
  The name of a feed of a person who was erased on request (ADR 0105): the
  name that they gave becomes "Feed of former member N", and the old name
  is redacted in the versions of the feed (`Rescord.Redaction`).
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    number = Ash.Changeset.get_argument(changeset, :former_number)

    changeset
    |> Ash.Changeset.force_change_attribute(:name, "Feed of former member #{number}")
    |> Ash.Changeset.after_action(fn changeset, feed ->
      Rescord.Redaction.redact_versions(changeset.resource, [feed.id], [:name], changeset.tenant)
      {:ok, feed}
    end)
  end
end
