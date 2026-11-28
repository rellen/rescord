# ADR 0117: Residents in care, a census against the room

Status: accepted. The second chart of issue 36, which the maintainer chose
to build with the other nine on 28 November 2026 (ADR 0116).

## Context

A refuge asks how full it is, and whether it was over its room. The
records hold the answer: each resident has an arrival, maybe a departure,
and each location maybe a capacity. No page shows it over time. Issue 36
proposes a step line of the residents in care each day, with a rule at the
room, and bars of the arrivals and the departures of each week.

## Decision

1. **A stay is an arrival and maybe a departure.**
   `Rescord.Residents.stays/1` reads them as the actor, with `select`, and
   leaves out a resident with no date of arrival, which no day can count.
   A species narrows it.
2. **The counts are pure**: `Rescord.Residents.Census` (`by_day/3`,
   `by_week/2`, through the delegates `in_care_by_day/3` and
   `moves_by_week/2` of the domain, for the boundary). A resident is in
   care at the end of a day when it arrived on that day or before and has
   not left by then, as `Rescord.Reports.Facts.Register.in_care_on/2`
   says. A count starts from the stays before the window and adds the
   change of each day, so 365 days cost one pass over the stays.
3. **The room is the sum of the capacities**: `Rescord.Locations.room/1`.
   A location with a capacity counts with it, and the locations inside it
   do not count again; a location with none counts the room of those
   inside it. `nil` when no location has a capacity, and then the page has
   no rule and no figure of the days over room. A species does not narrow
   the room: a location holds residents of any species.
4. **The page** is `RescordWeb.ResidentsInsightsLive` at
   `/o/:organisation/insights/residents`: four figures (in care today, the
   arrivals, the departures, the days over room), a step line of the last
   365 days, bars of the last 52 weeks, and the counts of each week as a
   table in a `<details>`. Each member can open it.
5. **Two new parts of a chart.** `line_chart/1` takes `step` (a line that
   holds its value to the next point, `Chart.step_path/1`) and `rules`
   (dashed lines across the plot at values, in `--field`). The new
   `updown_bars/1` draws a pair of counts for each column: the first above
   a middle line in `--accent`, the second below it in `--field`. The
   place says which is which, and the key says it in words; the colours
   are the one series and the context of ADR 0080, so no new token.

## Consequences

- The room is what the capacities say today. A capacity that changed in
  the year draws the rule of today over the whole year.
- A resident whose arrival was recorded late counts from the day of its
  arrival, so a day of the past can gain a resident after it was looked
  at.
- `Chart.bars/1`, `updown_bars/1` and the `step` line are there for the
  next charts: the stock and days left, and the lengths of stay.
