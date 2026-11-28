defmodule Rescord.Inventory.Calculations.Stock do
  @moduledoc """
  The stock of each item of a read: its level, its lots, and what is wrong
  with it, as `Rescord.Inventory.stock/1` gives it (ADR 0088).

  Rescord stores no level. This calculation reads the lots, the stock
  movements and the reorder levels of the items of the read, and of no
  other item, as the actor of the read. So a page of a collection reads
  the movements of the items of that page.

  The database cannot sort or filter on it: the rule is in Elixir, in one
  place. `Rescord.Inventory.with_fault/3` narrows a query to the items
  with a fault.
  """

  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:reorder_level, category: [:label], unit: [:label]]

  @impl true
  def calculate(items, _opts, context) do
    Rescord.Inventory.stock_of(items,
      actor: context.actor,
      tenant: context.tenant,
      authorize?: context.authorize?
    )
  end
end
