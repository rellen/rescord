# ADR 0121: Stays, and the time line as a list

Status: accepted. The fifth chart that is built of issue 36 (its chart
4), which the maintainer chose to build with the other nine on
28 November 2026 (ADR 0116).

## Context

A refuge asks who came when, and who has been here longest. Issue 36
proposes a Gantt chart: a row for each resident, a bar from the arrival to
the departure on one scale of time, dashed for a stay that goes on, with
the name as a link and how the stay began, how long it is and how it
ended. The medication courses (chart 6) and the story of a resident
(chart 10) are time lines too, so the part is shared.

## Decision

1. **A time line is a list**: `timeline/1` of
   `RescordWeb.ChartComponents`, a `figure[data-timeline]` with an `<ol>`
   named by `label`. Each row has its name as a link and a note that says
   in words what its bars show, so the bars are decoration
   (`aria-hidden`): a screen reader reads the list, and a bar adds nothing
   that the note does not say. The design gave each bar `role="img"` and
   an `aria-label`; that read each value twice.
2. **The geometry** is `RescordWeb.Chart.span/4` and `day_x/3`, on a
   scale of whole days where each day is a slot, and `Chart.months/2` for
   the marks of the months. Places are percentages, as in ADR 0080.
3. **The scale** is SVG text over the bars, and a line for each mark in
   each row. A phone shows the label of each quarter and puts the name
   above its bar; a wider screen shows each month and puts the name beside
   the bar.
4. **A span that goes on** is dashed and lighter (`data-open`): it has no
   end yet. The key says both kinds in words.
5. **The page** is `RescordWeb.StaysInsightsLive` at
   `/o/:organisation/insights/stays`: a row for each resident in care on a
   day of the last 12 months, from `Rescord.Residents.stays/1`, in the
   order of the arrivals or of the lengths. A species narrows it. Each
   member can open it.
6. **No order by location yet**, which the design proposed. It needs the
   places of a resident over a range, which the story of a resident
   (chart 10) builds.

## Consequences

- The list has a row for each stay of the year with no limit. A refuge
  with a few hundred stays a year gets a long page; a page of its own for
  each part of the year can come if one asks.
- A stay that began before the window starts at its left edge, and its
  note gives its real dates.
- `timeline/1` takes several bars in a row, for the courses of a
  resident and the lanes of chart 10.
