# ADR 0065: The first page of an organisation says what needs attention

Status: accepted (the maintainer chose it on 28 November 2026, as the
second of the concepts of the review of Chironium: "A 'needs attention'
dashboard in place of the list of links on the first page of an
organisation", and "use your best judgement"). It adds to ADR 0024,
ADR 0037 and ADR 0061.

## Context

The first page of an organisation was a list of thirteen links. A member
who opened Rescord beside the animals learned nothing from it, and went to
the tasks, then to the inventory, then to the housing, to find what needed
somebody.

Rescord already calculated most of the answers, each on its own page:

- a task is overdue when it is due and its time is before now
  (`Rescord.Tasks.phase/2`, ADR 0032), and a routine makes tasks (ADR 0033);
- the stock of an item is below a reorder level, is past its expiry date,
  expires soon, or is below zero and asks for a count
  (`Rescord.Inventory.stock/1`, ADR 0034);
- a resident with no arrival is expected, and an absence has a day on which
  the resident is expected back (ADR 0025);
- a location has more residents than its capacity
  (`Rescord.Locations.tree/1`, ADR 0029);
- a transfer and a partner request wait for an answer (ADR 0042).

The concept is from the review of Chironium, which has a page of what is
pending. Nothing was copied: Chironium is under the AGPL, and this page is
written for the domains and the grants of Rescord. The review named three
faults that Chironium found in its own page: its list had no limit, it did
not read again by itself, and a thing that was due today read as late.

## Decision

- **The first page of an organisation says what needs attention now.** The
  page at `/o/<short name>` starts with a line that says how many things
  need attention, and then a section for each part of the organisation
  with something in it. The links to each part stay below, in a `nav`: the
  routines, the roles, the partner refuges, the transfers and the export
  are not in the site menu (ADR 0061), so the first page still leads to
  them.
- **Each domain says what needs somebody in its own part.** A domain has a
  function `attention`, as a domain has its grants (ADR 0024) and its
  changes for the timeline (ADR 0035). It returns `%{rows: rows, total:
  total}`, and a row is a map with a `kind`, the `record` that a person
  opens to act, and what else the domain says about it.
  `Rescord.Attention.parts/2` asks each domain, and knows nothing of what a
  row means. It is a boundary of its own, as `Rescord.Export` is. The
  parts today:

  | Part | Function | Rows |
  | --- | --- | --- |
  | Tasks | `Rescord.Tasks.attention/2` | each task that is due and whose time is before the end of today, the oldest first: overdue, or due today |
  | Stock | `Rescord.Inventory.attention/2` | each item to count, to order, with stock past its expiry date, and then each item with stock that expires soon |
  | Residents | `Rescord.Residents.attention/2` | each resident that is away past the day that it was expected back, and then each resident that is expected |
  | Housing | `Rescord.Locations.attention/2` | each location over its capacity |
  | Transfers and partners | `Rescord.Transfers.attention/3` | each transfer that the refuge received and did not answer, and then each refuge that asks to be a partner |

  A task of a routine is a task, so a routine has no rows of its own.
- **A person sees what they can read.** Each read runs as the person, with
  the organisation as the tenant, so the policies decide. No read here
  passes `authorize?: false` for a record that it shows.
- **A person sees what their role can act on.** A row is there only for a
  role with a grant for the action that puts it right: `complete` for a
  task, the stock movement that cures the fault for an item (`count`,
  `receive`, `discard` or `use`), `finish` of an absence, `record` of an
  arrival, `move` of a placement, and `accept` for a transfer and for a
  partner request. A role that only reads opens each page, and nothing
  needs it on the first page. The role decides only what is left out: a
  caller that gets the role wrong shows no record that the policies
  refuse.
- **A part has a limit.** A part shows at most 8 rows
  (`Rescord.Attention.limit/0`), the ones that cannot wait first, with the
  number of all of them and a link to its page. A read that can be long (the
  tasks, the residents, the transfers) has the limit in its query, and
  counts in a query of its own.
- **Today is a day of the organisation.** A task of today is a task before
  the end of today in the time zone of the organisation (ADR 0026). A task
  of today whose time is to come reads "Due", and not "Overdue".
- **A row is a link, and the page of the record does the work.** A row is
  the name of the record, its state as a shape and a word, and a few
  facts. It has no button. A task has no page of its own, so its row opens
  the page of the tasks at the row of the task (`#task-<id>`), and a
  transfer and a partner request open their lists in the same way.
- **The page reads again each minute.** The LiveView sends itself a message
  each minute and reads the parts again. The time alone makes a task
  overdue, and no write says so, so the page needs a clock in any case. The
  same read finds what another member did. No resource has a notifier
  today (ADR 0062), so a notification is not what the page waits for. The
  line that says how many things need attention has the role `status`, so
  a screen reader says it again when the number changes.
- **The parts are function components** (ADR 0037), in
  `RescordWeb.AttentionComponents`. The state of the page is the list of
  the parts, which the LiveView holds: there is no widget and no nested
  LiveView.
- **The markup is a list.** A part is a `section` with a heading and a
  `<ul data-attention>`. On a phone the whole row takes the press, and is
  as high as a finger (ADR 0061). From 60rem two parts are side by side.
  There is no script.

## Consequences

- A member sees the work of the day on the page that opens first, and
  reaches each record with one press.
- A new thing that needs somebody is a row of its domain: a clause in the
  function `attention` of the domain, and a clause of `row/1` in
  `RescordWeb.AttentionComponents`. A new domain adds a line to
  `Rescord.Attention.parts/2`, and a title to the components.
- `Rescord.Inventory.faults/1` now says what is wrong with the stock of an
  item, and `RescordWeb.InventoryWords` has the words of each fault. The
  page of an item and the first page say the same words.
- The page costs a few queries for each part at each read, and reads each
  minute while it is open. The read of the stock takes each stock movement
  of the organisation, as the page of the inventory does. The read of the
  housing is left out when no location has a capacity.
- **The site menu has no count.** The review proposed one, from the same
  functions. Each page would then pay the reads of the first page. A count
  needs a cheaper read, or a notifier that says when it changed, and is
  left for then.
- A change of another member shows after a minute at most, and not at
  once. When the resources get a notifier (ADR 0062), the page can also
  read when a notification comes, and the clock stays for the time.
- Things that Rescord does not calculate yet are not on the page: a
  resident in care with no place, a prescription with no task, and a
  diagnosis that is still open. Each needs a decision of the domain first.
- The first page is as long as its work. With nothing to do it is one
  line, an explanation, and the links.

## Tests

- `Rescord.AttentionTest` holds what is in each part, the order, the
  limit, the day of the organisation, and who sees a row. Each rule of a
  role was broken one time, and a test failed.
- `RescordWeb.AttentionPagesTest` holds the page: the rows and their
  links, the words, the empty page, the read by the clock, and the links
  to the parts.
- `RescordWeb.Features.AttentionTest` holds the page in a browser, with a
  screen of 320px and of 360px: nothing is wider than the screen, a press
  anywhere on a row finds its link, the row of a task opens the tasks at
  that task below the site bar, and the focus shows around a row.
