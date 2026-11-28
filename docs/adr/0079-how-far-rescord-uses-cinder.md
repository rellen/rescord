# ADR 0079: How far Rescord uses Cinder, and where it should use more

Status: proposed (the maintainer asked on 28 November 2026: "are we making
full use of Cinder?"). This is an assessment. It changes no code. Each
proposal below waits for the maintainer.

## Context

ADR 0014 made Cinder the way to show a collection of records, and settled
the two rules that Cinder does not fit as it comes: its Tailwind classes
(a theme with almost no class, and the layer `vendor` of the stylesheet)
and its LiveComponent (it is its own, and we write none). ADR 0017 made the
sort of a table column work from the keyboard. Nobody had looked since at
how many pages follow ADR 0014, or at how much of Cinder those pages use.

This ADR read each page of `lib/rescord_web/`, the function of the domain
behind each list, and the source and the usage rules of Cinder at the
version of `platform/mix.lock`: 0.18.1, which is the newest on Hex
(1 November 2026).

## The answer in short

No. Three collections of about twenty are a `Cinder.collection`, and those
three use a small part of it. Nothing stands in the way of more: the theme,
the stylesheet and the test of ADR 0014 hold for each new collection.

| Collection | Shown with | Filters, sort, pages |
| --- | --- | --- |
| Residents | Cinder, table | a search on the name, a sort, two choice filters, pages of 25 |
| Members | Cinder, table | pages of 25, and nothing else |
| Organisations (root page) | Cinder, table | a text filter, a sort, pages of 25 |
| Stock history of an item | a table by hand | the newest 100 movements, and no way to the older ones |
| Journal of a resident | a list by hand | each entry, each time; `?only=medical` is a filter by hand |
| Items of the inventory | a table by hand | each item; no search, no filter |
| Tasks of a day | a table by hand | one day (`?day=`), each task of it |
| Photos of a resident | a grid by hand | each photo; an album is a filter by hand |
| Routines, groups, suppliers, partners, lists, roles, transfers, calendar feeds, the providers of the assistant | a table or a list by hand | each record; none |
| Timeline of a resident | a list by hand | each event; none |
| Housing | a tree by hand | none |

## What the three collections do not use

- **The state in the address** (`use Cinder.UrlSync`, `url_state`). A member
  filters the residents, opens one, and goes back: the filter, the search,
  the sort and the page are gone. A filtered list has no address to keep or
  to send. This is the largest gap, and the smallest change.
- **The members table turns nothing on.** No column has `sort`, `search` or
  `filter`.
- **A filter on a field that is not a column** (`<:filter>`): the species
  and the location of a resident, the role of a member.
- **A choice of the size of a page** (`page_size={[default: 25, options:
  [...]]}`).
- **The empty state** (`<:empty :let={context}>`, with `context.filtered?`).
  "No resident matches the filters" and "the register has no resident yet"
  are different things to say, and each collection says the same words of
  Cinder for both.
- **The list and the grid layout.** ADR 0014 gave both their rules in
  `vendor.css`, and no page uses one.
- **The query that the filters built** (`on_query_change`). A report or an
  export of "what the list shows now" can take it.
- **Selection and actions on many rows.** ADR 0014 says that no browser has
  shown their rules yet. Not now.

## What a list needs before Cinder can show it

These facts decide the cost of each move. They are from the source of
Cinder and from the three collections that we have.

- Cinder reads an Ash query, with pages from the action. A list that Elixir
  builds from more than one read is not a query: the levels of the
  inventory (`Rescord.Inventory.stock/1` adds up each movement), the
  timeline (journal entries merged with the history of several resources), the
  words of a group.
- The page does not see the rows that Cinder read. What a row shows is a
  load of the query, or something that the page reads once for the whole
  organisation (the portraits of the residents list). The journal reads the
  attachments of its entries in a second read by their ids: that must
  become a relationship.
- An action that is not the default read needs `pagination`, or Cinder
  reads each record and shows no pages. `defaults [:read]` has it.
- Cinder loads after the page mounts. A test waits with `render_async`.
- Each table of Cinder has the gaps in accessibility that ADR 0014 lists and
  ADR 0017 leaves open: the choice filter says nothing of its state, and the
  pages are not a `nav`. A table by hand has none of them.

## Proposals

Use more of Cinder where we have it:

- **U1. The state of each collection in the address.** Residents first, then
  members and organisations. No change to the data.
- **U2. Turn on what the columns can do.** Members: a sort and a search on
  the email address, a filter on the role. Residents: a filter on the
  species, and a choice of the size of a page.
- **U3. Two empty states** for each collection: nothing yet, and nothing
  that matches.

Move a list to Cinder:

- **M1. The stock history of an item.** The table stops at 100 movements
  today. With Cinder it has pages, and filters on the kind of movement, the
  lot and the date. The lot becomes a load. No change to the data.
- **M2. The journal of a resident**, in the list layout: filters on the
  kind and the date, a search in the text, pages. `?only=medical` becomes a
  filter of Cinder with the same address. The attachments become a
  relationship of the entry. This is the largest move: the page also has
  the forms of an entry, and other work changes the journal page now.
- **M3. The items of the inventory.** First the level of an item must be an
  aggregate or a calculation of the resource, which is worth it by itself:
  the page reads each movement of the organisation each time it opens.
  Then a search, a filter on the category and on "below its reorder level".
- **M4. The tasks of a day.** The day stays the query; Cinder adds filters
  on the person, the kind and the state.
- **M5. The photos of a resident**, in the grid layout, for pages.

Do not move:

- **Routines, groups, suppliers, partners, lists, roles, transfers,
  calendar feeds, providers.** Each has tens of records. Cinder would add a
  load after the mount and its gaps in accessibility, and take nothing off
  the page. ADR 0014 is about a collection with filters, a sort or pages.
  Move one when it grows: groups are the first that could.
- **The timeline and the housing tree.** Neither is a query, and a tree is
  not a collection.

A new list (expenses, conditions) follows ADR 0014 from its first commit.

**The order that this ADR proposes:** U1, U2 and U3 together, then M1, then
M2 when the journal page is quiet, then M3. M4 and M5 when somebody asks.
With M1 or M2, close the two open gaps of ADR 0017 in
`assets/js/cinder_tables.ts`, because more members then meet them.

## Consequences

- Nothing changes until the maintainer chooses. A proposal that he chooses
  gets its design as an issue, and its own ADR if it decides something new.
- No proposal needs a new dependency or a migration. M2 and M3 add a
  relationship or an aggregate, which are code and not columns.
- AGENTS.md already says that a collection is a `Cinder.collection`. It does
  not yet say when a plain table is right. If the maintainer agrees with
  "Do not move", that sentence goes there: a table with no filter, no sort
  and no pages, of a list that stays short, is a table by hand.
