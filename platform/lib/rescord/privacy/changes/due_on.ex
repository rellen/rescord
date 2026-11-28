defmodule Rescord.Privacy.Changes.DueOn do
  @moduledoc """
  The day that a request is due: one calendar month after it arrived, or
  after the identity was confirmed when that came later (ADR 0105). A
  month after 31 January is the last day of February, as the ICO counts.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      Ash.Changeset.force_change_attribute(changeset, :due_on, due_on(changeset))
    end)
  end

  @doc "One calendar month after the later of the two days."
  @spec due_on(Ash.Changeset.t()) :: Date.t()
  def due_on(changeset) do
    received = Ash.Changeset.get_attribute(changeset, :received_on)
    confirmed = Ash.Changeset.get_attribute(changeset, :identity_confirmed_on)

    start =
      if confirmed && Date.compare(confirmed, received) == :gt, do: confirmed, else: received

    Date.shift(start, month: 1)
  end
end
