# ADR 0084: The state of a collection in the address, and the stock history with Cinder

Status: accepted (the maintainer chose proposals U1, U2, U3 and M1 of
ADR 0079 on 28 November 2026, with M2 and M3, which get their own ADR).
The design is issue 14.

## Context

ADR 0079 found that the three collections of Cinder used a small part of
it, and that the stock history of an item stopped at its newest 100
movements.

- A member who filtered the residents, opened one and went back found the
  list with no filter. A filtered list had no address.
- The members table had no search, no sort and no filter.
- A collection said the same words of Cinder for "nothing yet" and for
  "nothing matches".
- `Rescord.Inventory.history/2` read 100 movements, and the page had no
  way to the older ones.

## Decision

- **A collection that is the page keeps its state in the address.** The
  LiveView has `use Cinder.UrlSync`, and the collection gets
  `url_state={@url_state}`: the residents, the members, the organisations
  of the root page.
  - Cinder writes a parameter for each filter, by the name of its field,
    and `search`, `sort`, `page` and `page_size`. It keeps a parameter that
    is not its own.
  - The names have no prefix, so one collection of a page takes the state
    of the address.
  - The page reads none of these parameters. Cinder reads them, makes no
    atom from a value, and ignores a name that is no field of the
    collection and a value that is no choice. The page tests send both.
- **A collection that is a part of a page does not.** The stock history
  of an item keeps its filters in the page alone.
- **Each collection has two empty states**, in an `<:empty>` slot: nothing
  matches the search and the filters, and there is nothing yet.
- **Residents:** a filter on the species, which is no column
  (`<:filter>`), with each species of the organisation, a retired one too,
  because a resident can still have it. A choice of 25, 50 or 100
  residents on a page.
- **Members:** a filter on the role, with each role of the organisation,
  and a search on the email address.
  - The email address of a member is a calculation in Elixir: the user is
    in no schema of an organisation, and a user reads only their own
    record. Cinder cannot search or sort on such a field. So the search
    goes through `Rescord.Accounts.members_with_email/2`, which reads the
    users with no policy, as the calculation does, and gives back only a
    filter on the members. The query still answers with the members that
    its actor can read, in its organisation.
  - **The members have no sort on the email address.** Issue 14 proposed
    one. It needs the address as an expression of the database, which is a
    change to how a member reaches its user, and an organisation has tens
    of members. Not now.
- **The stock history of an item is a `Cinder.collection`**, with pages of
  25, 50 or 100, a filter on the date, on the kind of movement and on the
  lot, and a sort on the time.
  - `Rescord.Inventory.query_to_history/2` returns the query: the
    movements of the lots of the item, the newest first, each with its
    lot. It is a function of the domain and not a `define`, because the
    web layer cannot write the filter through the lot.
  - `history/2` is gone. Nothing but the page read it.
  - The levels of the lots, above the history, stay a table by hand: the
    list is short, and Elixir works the levels out.

## Consequences

- No migration, and no new dependency.
- The address of the residents page has `sort=name` after the first
  change of a filter: Cinder writes the sort that the query starts with.
- A browser showed, on the day of this record: the filter of the residents
  survives a press of Back from the page of a resident; the filters, the
  empty states and the pages at 360 and at 1280 pixels, in both schemes.
  `RescordWeb.Features.PhoneTest` visits the three pages and the page of
  an item at 320 pixels.
- The count of active filters of Cinder ("1 active") does not count the
  search. That is the markup of Cinder.
- The stock history now reads the lot of each movement through the
  relationship, in one query with the page.
- More pages have the choice filter and the pages of Cinder, with the two
  gaps in accessibility that ADR 0017 left open. They are the next step.
