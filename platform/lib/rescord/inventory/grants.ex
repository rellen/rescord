defmodule Rescord.Inventory.Grants do
  @moduledoc """
  What a role can do with the inventory of an organisation (ADR 0024 and
  ADR 0034).

  Each role reads the inventory. The power `:stock` records what happens
  to the stock: a delivery, a use, a move, a discard and a count. That is
  the daily work of each member. The power `:inventory` keeps the list of
  the items, the suppliers and the reorder levels. Only the administrators
  have it at first (ADR 0040).

  No role has a grant for `move_in` of a stock movement: Rescord runs it
  itself, as the second half of a move.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Inventory.{Item, Lot, ReorderLevel, StockMovement, Supplier}

  @impl true
  def reads do
    for resource <- [Item, Supplier, ReorderLevel, Lot, StockMovement],
        do: {resource, :read, :all}
  end

  @impl true
  def powers do
    %{
      stock:
        for(action <- [:receive, :revise], do: {Lot, action, :all}) ++
          for(
            action <- [:receive, :use, :discard, :count, :move],
            do: {StockMovement, action, :all}
          ),
      inventory:
        for(action <- [:add, :revise, :remove], do: {Item, action, :all}) ++
          for(action <- [:add, :revise, :remove], do: {Supplier, action, :all}) ++
          for(action <- [:set, :change, :clear], do: {ReorderLevel, action, :all})
    }
  end
end
