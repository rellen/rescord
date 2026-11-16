defmodule Rescord.Inventory.Grants do
  @moduledoc """
  What a role can do with the inventory of an organisation (ADR 0024 and
  ADR 0034).

  Each member reads the inventory and records what happens to the stock:
  a delivery, a use, a move, a discard and a count. That is the daily work.
  An administrator also keeps the list of the items, the suppliers and the
  reorder levels.

  No role has a grant for `move_in` of a stock movement: Rescord runs it
  itself, as the second half of a move.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Inventory.{Item, Lot, ReorderLevel, StockMovement, Supplier}

  @member [
            {Item, [:read]},
            {Supplier, [:read]},
            {ReorderLevel, [:read]},
            {Lot, [:read, :receive, :revise]},
            {StockMovement, [:read, :receive, :use, :discard, :count, :move]}
          ]
          |> Enum.flat_map(fn {resource, actions} -> Enum.map(actions, &{resource, &1, :all}) end)

  @administrator [
                   {Item, [:add, :revise, :remove]},
                   {Supplier, [:add, :revise, :remove]},
                   {ReorderLevel, [:set, :change, :clear]}
                 ]
                 |> Enum.flat_map(fn {resource, actions} ->
                   Enum.map(actions, &{resource, &1, :all})
                 end)

  @impl true
  def grants, do: %{administrator: @member ++ @administrator, member: @member}
end
