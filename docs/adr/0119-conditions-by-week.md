# ADR 0119: Conditions by week, a table of counts

Status: accepted. The third chart of issue 36, which the maintainer chose
to build with the other nine on 28 November 2026 (ADR 0116).

## Context

A refuge asks whether something is spreading. The conditions of the
residents are episodes (ADR 0083), each with the day it started and maybe
the day it ended. The page of the conditions counts them by month, which
is too coarse to see a week of new cases. Issue 36 proposes a table of
counts: a row for each condition, a column for each of the last 12 weeks,
stronger in colour for more new cases, and the cases that go on now.

## Decision

1. **The counts** are `Rescord.Journal.conditions_by_week/2`: it reads, as
   the actor and with `select`, the episodes that started in the weeks or
   have no end, and groups them in Elixir. A row is a condition with a new
   case in the weeks or a case that goes on, the most new cases first. A
   case goes on while it has no end and its resident is in care or away,
   as `conditions_now/1` counts.
2. **The page** is `RescordWeb.ConditionsInsightsLive` at
   `/o/:organisation/insights/conditions`: one `heat_table/1` of the
   variant `"numbers"`, with a column for each week, a column "Now" of the
   cases that go on, and a last row "All" of the totals. Each count of a
   week is a step of the ramp against the most new cases of one condition
   in one week. A count that is no step, such as a total, has the new
   level `:total`: no ground, and a strong number. A count of none is
   quiet. Each member can open it.
3. **The heads fit a phone.** A week shows the day of its Monday, and its
   month above it where a month starts ("Sept 7", "14", "21"); a screen
   reader hears "Week of 7 September 2026". On a wider screen the names of
   the rows get 8rem.
4. **No filter by location yet**, which the design proposed. The location
   of a resident on the day that a case started needs the places of a
   resident over a range, which the story of a resident (chart 10)
   builds. The filter comes with it.

## Consequences

- A diagnosis from before ADR 0083 has no episode, so the weeks before
  that release show no case.
- A case that started in a week that is not on the table, and goes on,
  counts in "Now" and not in a week.
- The level `:total` is there for the punch card of the hours (chart 7)
  and any later table of counts.
