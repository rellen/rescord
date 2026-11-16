defmodule Rescord.Inventory.MovementKind do
  @moduledoc """
  Why a quantity of a lot came into a place or went out of it
  (`docs/domain.md`, section 5.8, and ADR 0034):

    * `:received` - the organisation got it;
    * `:used` - a member used it;
    * `:moved` - a member moved it from one place to another: one movement
      out, and one movement in;
    * `:discarded` - a member threw it out;
    * `:counted` - a member counted the place, and the count was not the
      level.

  A page shows the words of `RescordWeb.InventoryWords`, and never the atom.
  """

  use Ash.Type.Enum, values: [:received, :used, :moved, :discarded, :counted]
end
