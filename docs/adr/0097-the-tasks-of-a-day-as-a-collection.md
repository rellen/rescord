# ADR 0097: The tasks of a day are a collection

Status: accepted (the maintainer chose proposal M4 of ADR 0079 on
28 November 2026; the design is in issue 14).

## Context

The tasks page showed each task of one day, and on today each task of an
earlier day that was still due, in a table of its own. A member could not
see only their own tasks, only the tasks that were still due, or only one
kind (ADR 0079).

The page is more than a list. It has the form of a new task, the buttons
of each task (Take, Done, Open again) and the form that skips one. The
first page (ADR 0065) and a calendar feed (ADR 0074) link to one task with
`tasks?day=<date>#task-<id>`.

## Decision

1. **The tasks are one collection of Cinder**, a table, on
   `Rescord.Tasks.query_to_day/2`: the tasks of the day, in the order of
   their times. On the page of today the query also has each task of an
   earlier day that is still due. Those come first, because their times
   are earlier, and show their day with their time. They are one list and
   not two, so that a filter holds for both.
2. **Filters and a search:**
   - `state`: due, done or skipped. Overdue is no state: a task that is
     due shows "Overdue" when its time is past.
   - `kind_id`: the kind of the task, from each kind of the organisation,
     a retired kind too.
   - `who`: "Me", "Anybody" (the tasks that name no member, which are for
     each member) or one member. The people of a task are a list of ids,
     so `Rescord.Tasks.for_person/2` narrows the query. The design said
     "Nobody"; the choice has the word of the column "Who", "Anybody".
   - A search on the title.
3. **Pages of 50, 100 or 200 tasks**: a member reads a day as one sheet.
   There is no sort: the order is the time.
4. **The state of the collection is in the address** (ADR 0084), so
   `?state=due&who=me` is what is left for a person. `day` stays a
   parameter of the page. The links "The day before", "Today" and "The day
   after" give the other parameters back, without `page`.
5. **The page does not hold the tasks.** An event (take, complete, skip,
   open again) reads its task again, as the person, with
   `Rescord.Tasks.task_of_day/3`: only a task that the day of the page
   shows. After the action the page tells the collection to read again
   (`Cinder.Refresh.refresh_table/2`), and the search, the filters and the
   page stay. Before, the page opened again at its own address.
6. **A task that another member changed a moment before** is now in its
   new state when the page reads it again, so the state machine refuses
   the action with `AshStateMachine.Errors.NoMatchingTransition`, and no
   longer with `Ash.Error.Changes.StaleRecord`.
   `Rescord.Accounts.error_messages/1` gives both the same words:
   "Somebody changed this a moment ago. The page shows it as it is now".
7. **The title of a task carries the id `task-<id>`**, because Cinder
   writes the row and gives it no id. The links of the first page and of
   a calendar still find the task there.
8. The task sheet (PDF), the calendar feeds and the attention list do not
   change.

## Consequences

- The page reads one page of tasks. Before, it read each task of the day
  and each task that was still due.
- The title is the first column, and not the time: Cinder writes each
  cell as a `td`, so the row has no `th`, and on a phone the first cell is
  the title of the card (ADR 0061). The time has a `data-label`.
- The section "Still due from earlier days" is gone. A sentence above the
  table says that those tasks come first, each with its day.
- A link `tasks#task-<id>` finds its task only on the first page of the
  collection. A day with more than 50 tasks can put a task on a later
  page; then the link opens the page with no scroll. If that happens, a
  parameter of the page such as the `entry` of the journal (ADR 0092) is
  the fix.
- A row has no `id`, so after Done the focus stays in the cell of the
  buttons only because the cell stays in the page (`assets/js/focus.ts`).
  A filter that leaves the task out sends the focus to the first control
  of the table.
- A task that a member completes while the filter `state=due` is on
  leaves the list at once.
- The page hears a change of another person (ADR 0096) with the same
  call: it tells the collection to read again, silently, so the rows stay
  while Cinder reads. A task is not temporal, so the query of the page
  reads the present and needs no new `as_of`.
- No migration, no new dependency and no new power.
