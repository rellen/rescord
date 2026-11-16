defmodule Rescord.Journal.Changes.HappenedAt do
  @moduledoc """
  Gives a journal entry the time that the thing happened: the time that the
  member gave, or the instant of the write when they gave none. The time is
  never after that instant (`docs/domain.md`, section 4).
  """

  use Ash.Resource.Change

  # The change reads the instant of the action, and not the clock, when the
  # action has one.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context) do
    now = instant(changeset)

    case Ash.Changeset.get_attribute(changeset, :happened_at) do
      nil ->
        Ash.Changeset.force_change_attribute(changeset, :happened_at, now)

      %DateTime{} = happened_at ->
        if DateTime.compare(happened_at, now) == :gt do
          Ash.Changeset.add_error(changeset, field: :happened_at, message: "cannot be after now")
        else
          changeset
        end
    end
  end

  defp instant(%{as_of: %DateTime{} = instant}), do: instant
  defp instant(_changeset), do: DateTime.utc_now()
end
