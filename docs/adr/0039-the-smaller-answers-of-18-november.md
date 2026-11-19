# ADR 0039: The smaller answers of 18 November 2026

Status: accepted (the answers are from the maintainer, 18 November 2026).

## Context

The maintainer answered six questions about parts that Rescord already
has. Each answer changes a rule of a resource, and none needs a new
domain.

## Decision

- **The units of a kind of measurement.** `Rescord.Lists.MeasureKind` has
  `unit_ids`: the ids of the units of the list of the organisation that a
  measurement of that kind can have. An administrator changes them on the
  lists page with `set_units`. The journal form offers only those units.
  `Rescord.Journal.Validations.UnitOfKind` refuses another unit on a write
  and on a correction, after the policy. A kind with no unit in its list
  takes each unit, so an organisation that sets nothing sees no change.
- **Stock below zero.** A movement out can take more than the level of the
  lot in that place. The level is then below zero, and the stock of the
  item says `Count the stock` and names each place until a count puts it
  right. The record of the shelf is often wrong, and a refusal stopped a
  member who had already used the stock.
- **The days before expiry.** `Rescord.Lists.ItemCategory` has
  `soon_days`, from 0 to 3650. A lot expires soon in that number of days
  before its expiry date, or in 30 days when the category of its item has
  no number or the item has no category.
- **Routines for administrators.** Only an administrator starts, changes,
  pauses, resumes and ends a routine. A member reads the routines, and
  works through their tasks. The journal offers the link to a routine of a
  prescription only to a person who can start one.
- **Every number of days, from the last task.** A routine has `count_from`:
  `:first_day`, which counts the days from its first day as before, or
  `:last_done`, which counts them from the day when a member last
  completed or skipped one of its tasks. Only the pattern `:interval` keeps
  `:last_done`. Such a routine has the tasks of one day that are due at
  most. When a member finishes the last of them,
  `Rescord.Tasks.Changes.NextOfRoutine` runs `generate` of the routine in
  the same transaction, and `SyncTasks` makes the next day: `every` days
  after the day of the finish, and never on or before the day of the last
  task. The second rule keeps a task that a member finished ahead of its
  day from a next day that is that same day.
- **Tasks for several members.** A task and a routine have `assignee_ids`
  in place of `assignee_id`. An empty list means each member. The task is
  done when one of them completes it, and the state machine and the filter
  on the state already make the second completion `StaleRecord`. `take`
  adds the actor to the list, and `give` sets the whole list. The tenant
  migration copies each member into the new list before it removes the old
  column.

## Consequences

- No page shows a different thing to an organisation that sets no unit,
  no number of days and no `count_from`.
- A member can no longer start a routine. A test of a page signs in an
  administrator for that work.
- A routine that counts from the last task makes no task while one of its
  tasks is late. That is the meaning of the answer: the next day counts
  from the work, and not from the calendar.
- The forms of a task and of a routine show a box for each member in
  place of one select.
