defmodule Rescord.Lists.Changes.RangeFollowsStandardUnit do
  @moduledoc """
  A new standard unit of a measure kind takes the range with it (ADR 0117):
  the lowest and the highest convert to the new unit when the two units
  have the same dimension, and are emptied otherwise, or when the kind has
  no standard unit any more. The range is always in the standard unit.
  """

  use Ash.Resource.Change

  alias Rescord.Lists

  # The change reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, _context) do
    old_id = changeset.data.standard_unit_id
    new_id = Ash.Changeset.get_attribute(changeset, :standard_unit_id)
    range = {changeset.data.lowest, changeset.data.highest}

    cond do
      range == {nil, nil} or old_id == new_id ->
        changeset

      is_nil(old_id) or is_nil(new_id) ->
        empty(changeset)

      true ->
        with {:ok, from} <- known(old_id, changeset),
             {:ok, to} <- known(new_id, changeset),
             {:ok, lowest} <- convert(elem(range, 0), from, to),
             {:ok, highest} <- convert(elem(range, 1), from, to) do
          changeset
          |> Ash.Changeset.force_change_attribute(:lowest, lowest)
          |> Ash.Changeset.force_change_attribute(:highest, highest)
        else
          _does_not_convert -> empty(changeset)
        end
    end
  end

  defp empty(changeset) do
    changeset
    |> Ash.Changeset.force_change_attribute(:lowest, nil)
    |> Ash.Changeset.force_change_attribute(:highest, nil)
  end

  defp convert(nil, _from, _to), do: {:ok, nil}
  defp convert(value, from, to), do: Rescord.Units.convert(value, from, to)

  defp known(unit_id, changeset) do
    base = [tenant: changeset.tenant, authorize?: false, not_found_error?: false, load: [:label]]

    options =
      case changeset.as_of do
        %DateTime{} = instant -> [as_of: instant] ++ base
        _not_set -> base
      end

    case Ash.get(Lists.Unit, unit_id, options) do
      {:ok, %{} = unit} -> Lists.known_unit(unit)
      _none -> :error
    end
  end
end
