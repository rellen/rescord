# ADR 0088: The stock of an item is a calculation, and the items are a collection

Status: accepted (the maintainer chose proposal M3 of ADR 0079 on
28 November 2026; the design is in issue 14).

## Context

The inventory page read each item, each lot, each stock movement and each
reorder level of the organisation each time it opened, and showed each
item in one table. It had no search, no filter and no pages (ADR 0079).

Rescord stores no level (ADR 0034). `Rescord.Inventory.stock/1` calculates
the stock of each item in Elixir, and a collection of Cinder reads its
rows with a query of Ash (ADR 0014). So the stock had to become a thing
that a query can load. ADR 0079 said "an aggregate or a calculation".

## Decision

1. **`Rescord.Inventory.Item` has the calculation `stock`**
   (`Rescord.Inventory.Calculations.Stock`): the map that `stock/1` gives
   for one item. It calls `Rescord.Inventory.stock_of/2`, which reads the
   lots, the movements and the reorder levels of the items of the read,
   and of no other item, as the actor of the read. `stock/1`,
   `item_stock/2` and the calculation build the stock with one function,
   so the rule is in one place.
2. **The level is not an aggregate of the database.** The rule is not a
   sum:
   - Stock that is past its expiry date does not count for a reorder
     level, and "past" is by the date in the time zone of the
     organisation.
   - A reorder level can be for one location, so the level is by lot and
     by place.
   - Stock expires "soon" by the days of the category of the item.

   An aggregate in SQL would be a second copy of this rule, and two copies
   drift. A sort on the level has no use: one item counts bags and the
   next counts mL.
3. **The items of the inventory page are a collection of Cinder**, with
   its state in the address (ADR 0084): a search on the name, a filter on
   the category, a filter on the state of the stock, a sort on the name,
   and pages of 25, 50 or 100. A page of 25 items reads the movements of
   25 items.
4. **The filter on the state calculates in Elixir.** Its choices are
   "Needs attention" and each fault of `Rescord.Inventory.faults/1`. The
   `<:filter>` of Cinder takes a function, and
   `Rescord.Inventory.with_fault/3` calculates the stock of each item of
   the organisation, as `stock/1` does, and narrows the query to the ids.
   The value in the address is a word (`?state=short`), and
   `RescordWeb.InventoryWords.fault_of/1` finds its fault: the page makes
   no atom from it.

## Consequences

- A visit with no filter on the state reads less than before. A visit
  with that filter reads what each visit read before.
- The calculation is not public, and the database cannot sort or filter
  on it. It has the item with its category and its unit inside
  (`stock.item`), as `stock/1` gives it.
- An actor who can read no stock gets an item with no lot from the
  calculation, and nothing from `with_fault/3`. No such actor can read an
  item in the first place.
- The attention list, the stock report, the calendar and the page of an
  item read as before.
- The loads of a row go in the option `query` of the function of the
  code interface: `query_to_items(%{}, query: [load: [:stock]], ...)`. The
  option `load` of such a function does nothing to the query.
- No migration, no new dependency and no new power.
