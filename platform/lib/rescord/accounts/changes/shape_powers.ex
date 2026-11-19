defmodule Rescord.Accounts.Changes.ShapePowers do
  @moduledoc """
  Puts the powers of a role in one shape: each power one time, in the order
  of `Rescord.Accounts.Grants.power_keys/0`. A power that Rescord does not
  know stays, and `Rescord.Accounts.Validations.KnownPowers` refuses it.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts.Grants

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :powers) do
      powers when is_list(powers) ->
        order = Grants.power_keys()
        known = Enum.filter(order, &(&1 in powers))
        other = powers |> Enum.reject(&(&1 in order)) |> Enum.uniq()
        Ash.Changeset.force_change_attribute(changeset, :powers, known ++ other)

      _none ->
        changeset
    end
  end
end
