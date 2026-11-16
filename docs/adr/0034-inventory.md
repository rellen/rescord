# ADR 0034: The inventory

Status: accepted (the answer is from the maintainer; the rules below it are
decisions of this ADR that the maintainer can change)

## Context

Section 5.8 of `docs/domain.md` gives an organisation its inventory. The
maintainer answered that Rescord tracks the inventory by lot, with an expiry
date, and by location. The document proposed that a stock movement records
each change, that Rescord calculates the level, and that an item has a
reorder level in the whole organisation and in one location.

## Decision

- `Rescord.Inventory` is a domain of its own. It uses the lists and the
  locations. Each of its resources is temporal.
- **An item** has a name, a category and a unit. The category is the last
  list that an organisation can extend. The unit is a value of the list of
  units.
- **A lot** is one delivery of an item, with one expiry date or none, a code
  or none, and a supplier or none. A member makes a lot when its first stock
  comes. Nothing removes a lot.
- **A stock movement** says that a quantity of a lot came into a place or
  went out of it. Its quantity has a sign. No action takes the sign: each
  action takes a quantity that is more than zero, or a count. The kinds are
  received, used, moved, discarded and counted.
- **A place is a location, or no location.** An organisation with no housing
  on record keeps its stock in no place in particular.
- **Rescord stores no level.** `Rescord.Inventory.stock/1` adds the
  movements of each lot in each place. `Rescord.Inventory.Levels` holds the
  sums, with no database.
- **A movement out takes no more than the level** of the lot in that place.
  The action reads the lot with a lock before the write, so two members do
  not take the same stock.
- **A count corrects the level.** A member gives the number on the shelf,
  and Rescord writes the difference as a movement. A count that finds the
  same number writes a movement of zero: it records that a member looked.
- **A move is two movements** in one transaction: one out of the first
  place, and one into the second.
- **Nothing changes a movement, and nothing removes one.** A movement that
  is wrong gets a second movement that corrects it.
- **A movement has the time that it happened**, which a member can give, and
  which is never after now. The history is in the order of those times.
- **A lot is expired after its expiry date**, on the calendar of the
  organisation, and it expires soon in the 30 days before that date.
- **A reorder level** for the whole organisation is an attribute of the
  item. `ReorderLevel` holds a level for one location. The stock is short
  when the level is below the reorder level. Stock that is past its expiry
  date does not count for this.
- **Grants.** Each member reads the inventory and records what happens to
  the stock. An administrator keeps the items, the suppliers and the reorder
  levels.

## Consequences

- A member cannot record a use of stock that Rescord does not know. They
  record a count first.
- The level of a location does not include the locations inside it.
- `stock/1` reads each movement of the organisation. An organisation with
  many years of movements needs a sum in the database.
- 30 days is a constant. An organisation cannot change it.
- A task of the kind `medicate` does not change the inventory
  (`docs/domain.md`, section 5.7).
- No page shows the stock of one location across all the items.
- An item has no rule that its name is unique.
