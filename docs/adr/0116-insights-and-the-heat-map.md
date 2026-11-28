# ADR 0116: Insights, and the heat map as a table

Status: accepted. The maintainer chose to build all ten charts of issue 36,
in the order of the issue, on 28 November 2026. This ADR holds the shared
parts and the first chart, the care calendar. Each later chart adds its
own ADR.

## Context

Issue 36 proposes ten charts that answer the questions of a refuge from
its records: heat maps, a census, time lines, a tree map. Each is drawn by
the server, as the line chart of ADR 0080 is, with no script and no
library. The first chart is a calendar of the care: a square for each day
of the last 26 weeks, stronger in colour for a larger share of its tasks
done on time, and the tasks of the next two weeks.

A heat map is a grid of values. A grid of SVG would need a text
alternative of its own, and its words would be in a second place. A table
of HTML is the grid and its words at once. But a table becomes a list of
cards on a phone (ADR 0061), which a heat map cannot be.

## Decision

1. **A heat map is a table**: `heat_table/1` of
   `RescordWeb.ChartComponents`, `table[data-heat]`. The caption names it
   and says what it shows. Each header has short words that show and the
   whole words for a screen reader ("Jun" and "Week of 1 June 2026"), and
   each cell has its value in words ("6 of 9 on time, 1 late, 1 skipped,
   1 overdue"), so a screen reader reads a cell with its row and its
   column. The table stays a grid on a phone: its rules undo the rules of
   ADR 0061. With no variant, a cell is a square and its words are hidden
   from the eye. The variant `"numbers"` shows each count, with the day of
   the month small in the corner of the cell where it helps, and that
   small number is not read aloud: the headers say the day.
2. **One ramp of the lead colour, four steps.** `--heat-1` to `--heat-4`
   in `tokens.css` are the lead colour over the ground of a card at 18%,
   40%, 68% and 100%, written as hex so that `TokensTest` reads them. More
   is always nearer to the lead colour: light to dark in the light scheme,
   dark to light in the dark one, so the words of a page say "stronger",
   never "darker". The words on steps 1 and 2 are `--text`, on step 3
   `--on-heat-3`, and on step 4 `--on-accent`; `TokensTest` holds each
   pair to AA in both schemes. A step is never a state: a cell that needs
   a look has a dot, a shape, and its words say why.
3. **Steps of a count and of a share.** `Chart.level/2` puts a count on
   a step by the quarter of the greatest count of the map that it
   reaches. `Chart.share_level/3` puts a share on a step by bounds in
   percent; the care calendar uses 80%, 90% and 97%. Step 0 is a cell with
   nothing to count, and `:none` a cell with no value, such as a day to
   come.
4. **On time is done by the due time plus one hour**, the same for each
   refuge at first. `Rescord.Tasks.days/3` counts the tasks of each local
   day of the organisation: on time, late, skipped, overdue (still due,
   and its time has passed) and to come. A cancelled task is archived and
   no count has it. A week starts on a Monday (`Chart.weeks/2`).
5. **A count is a function of its domain** that reads as the actor, as
   `Rescord.Journal.conditions_started/2` does. It selects only the
   fields that it counts (`due_at`, `state`, `finished_at`) and groups
   them by the local day in Elixir. This changes judgement call 7 of
   issue 36, which proposed sums in SQL in a new `Rescord.Insights`: a
   sum in SQL would read outside the policy of the resource or need an
   aggregate for each day, and 26 weeks of a large refuge are a few
   thousand rows. When the metrics of a page (ADR 0077) say that a read
   is slow, a sum in SQL or a summary table can come then, with its ADR.
6. **The insights are a part of the page of the reports.** The page
   `/o/<short name>/reports` starts with a section "Insights", a card for
   each page of insights, and those pages are in the part Reports of the
   site menu. This changes judgement call 6 of issue 36, which proposed a
   menu entry of its own: the site bar of a wide screen holds its parts in
   one row (ADR 0061, `PhoneTest`), and with a long name of an
   organisation that row has no room for one more entry. A page of
   insights is below `/o/<short name>/insights/`.
7. **A cell takes a press and no focus**, as a point of a line chart
   does (ADR 0080): the table already holds each value for the keyboard
   and for a screen reader. A press on a day of the care calendar says its
   counts in a status line, with a link to the tasks of that day.
8. **No chart counts the work of a named person**: the care calendar
   counts the tasks of the refuge, and never who did them.
9. **A page of insights reads when it opens and when its filter
   changes**, and does not listen for changes (ADR 0096): it shows weeks
   of the past, which the change of one task hardly moves.

## Consequences

- The next charts of issue 36 use `heat_table/1` and the ramp: the
  conditions by week and the punch card of the hours.
- A heat map is as readable to a screen reader as any table, and a phone
  shows 26 weeks in its width with cells of about 8 pixels: the press on
  a day gives the words.
- The routines make the tasks of a few days ahead
  (`task_days_ahead`), so the next two weeks show only that many days: a
  day after them has no task yet, and is not shown as a day with none.
- A reopened task has lost its `finished_at` (only its versions keep it),
  and a routine makes no task for a time that has passed, so a pause or a
  job that did not run is a day with fewer tasks, not a day with missed
  ones.
