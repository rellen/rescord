# ADR 0120: When the care is done, a punch card

Status: accepted. The fourth chart that is built of issue 36 (its chart
7), which the maintainer chose to build with the other nine on
28 November 2026 (ADR 0116).

## Context

A refuge asks which hours are busy and which hours slip, to plan its
rosters. The tasks hold the time each was due and the time each was done.
Issue 36 proposes a punch card: a row for each day of the week, a column
for each hour, a dot as large as the tasks done then; and, for each hour,
the share of the tasks due then that were done more than an hour late.

## Decision

1. **The counts** are `Rescord.Tasks.hours/3`: it reads, as the actor and
   with `select`, the tasks done that were due in a range of days, and
   counts them in the time zone of the organisation. A task counts in the
   hour in which it was done, and, for the slip, in the hour of its time.
   Late is the rule of `days/3` (ADR 0116): done more than an hour after
   its time. A skipped or overdue task is no slip here: the care calendar
   counts it.
2. **The page** is `RescordWeb.HoursInsightsLive` at
   `/o/:organisation/insights/hours`, over the last 12 weeks. Two heat
   tables share the 24 columns of the hours, whose heads show a time each
   six hours ("6:00 am"). Each member can open it.
3. **A punch card is a heat table** of the new variant `"dots"`: the step
   of a cell is the size of its dot, in `--accent`, and an hour with no
   task keeps its place with a point in `--border`. As in each heat table,
   the words of a cell ("14 tasks done") are for a screen reader.
4. **The slip of an hour** is a row of squares, a step of the ramp for its
   share of late tasks: under 5%, 5%, 15%, and 30% or more. An hour with
   no task done has no step.
5. **No person.** The page counts the tasks of the refuge, never who did
   them (judgement call 3 of issue 36).

## Consequences

- The punch card tells when the work was recorded as done, which is not
  always when it was done: a member who ticks the tasks of a morning at
  noon makes noon look busy and the morning slip.
- A reopened task has lost its `finished_at`, and does not count.
