defmodule Rescord.Journal.Changes.EpisodeDay do
  @moduledoc """
  Gives a day of an episode the date of today when the action gives none:
  the first day of a new episode, and the last day of one that a member
  marks as resolved.

  Today is the date in the time zone of the organisation (ADR 0026), at the
  instant of the write.
  """

  use Ash.Resource.Change

  # The change reads the instant of the action, and not the clock, when the
  # action has one.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def init(opts) do
    if is_atom(opts[:attribute]), do: {:ok, opts}, else: {:error, "attribute must be an atom"}
  end

  @impl true
  def change(changeset, opts, _context) do
    attribute = opts[:attribute]

    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil ->
        Ash.Changeset.force_change_attribute(
          changeset,
          attribute,
          Rescord.Journal.Validations.EpisodeDays.today(changeset)
        )

      _given ->
        changeset
    end
  end
end
