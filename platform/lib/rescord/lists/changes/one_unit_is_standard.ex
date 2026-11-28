defmodule Rescord.Lists.Changes.OneUnitIsStandard do
  @moduledoc """
  A measure kind that gets exactly one unit, and has no standard unit, gets
  that unit as its standard unit (ADR 0094): one unit is a standard
  already.
  """

  use Ash.Resource.Change

  # The change reads the changeset only.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context) do
    case {Ash.Changeset.get_attribute(changeset, :unit_ids),
          Ash.Changeset.get_attribute(changeset, :standard_unit_id)} do
      {[only], nil} -> Ash.Changeset.force_change_attribute(changeset, :standard_unit_id, only)
      _other -> changeset
    end
  end
end
