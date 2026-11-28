# ADR 0080: Measurements over time, with charts that the server draws as SVG

Status: accepted (the maintainer asked on 28 November 2026 for measurement
tracking views that are mobile first, with research of the chart libraries
or a decision for our own code, and for the design first, as an issue: the
design is issue 12). It builds on ADR 0030 and ADR 0039 (the journal and
its measurements), ADR 0071 (units of measure) and ADR 0075 (the locale),
and adds to ADR 0004, ADR 0037 and ADR 0061.

## Context

A measurement is a journal entry of the kind `measurement`: a measure
kind, a decimal value and an optional unit. Rescord ships no measure kind.
Each organisation keeps its own list, and the weight is only the example
of the documents. So a view of the measurements cannot know "the weight":
it must serve each kind, with a unit that Rescord knows, with one that it
does not know, and with none.

The page of a resident showed the newest value of each kind. Nothing
showed the values over time, and the chart that a refuge asks for first is
the weights of a litter.

The chart packages on Hex were read on 28 November 2026. `contex` (0.5.0,
May 2023) and `plox` (0.3.0, March 2026) draw SVG on the server, and both
write classes, colours and sizes in pixels into the markup, and give no
text alternative. `matplotex` needs `nx`. `vega_lite` and `tucan` need the
scripts of Vega in the browser, or a Rust NIF on the server. `live_charts`
is a wrapper of ApexCharts, a script. `svg_charts` is a Rust NIF. Issue 12
has the table.

## Decision

- **A chart is our own function components, and no library.** Rescord
  needs one line chart and a sparkline. `RescordWeb.Chart` is the
  geometry, `RescordWeb.ChartComponents` has `line_chart/1` and
  `sparkline/1`, and the section "charts" of `components.css` is the look.
  The markup has no class and no colour: the stylesheet reads the tokens,
  so a chart follows both schemes.
- **A chart has no script of ours.**
  - The `<svg>` has no `viewBox`, and a place is a percentage
    (`cx="43%"`). One unit is one CSS pixel at each width, so a dot stays
    round and a word keeps its size on a phone and on a wide screen.
  - Only the line stretches. A `<path>` takes no percentage, so the line
    is in a nested `<svg viewBox="0 0 100 100"
    preserveAspectRatio="none">`, with `vector-effect:
    non-scaling-stroke`.
  - The numbers of the value axis and the two dates below the plot are
    HTML, beside and below the `<svg>`.
  - A pointer that hovers over the band of a point sees a rule, a ring and
    the words of the point, with CSS inside `@media (hover: hover)`. A
    press sends the LiveView event `pick`, and the page writes the point
    in words below the chart, with a link to its journal entry.
- **The geometry is exact.** The ticks are three to six round numbers at a
  step of 1, 2, 2.5 or 5 times a power of ten, computed with `Decimal`. A
  series of whole numbers has whole steps. The value axis starts at zero
  when the least value is at most half of the greatest, and no chart fills
  the area below its line. The time axis is true time, and names its first
  and its last date only.
- **A chart is one image with a name and a description, and its values are
  a table.** The `<svg>` has `role="img"`, an `aria-label`, and
  `aria-describedby` to the caption of the figure, which says how many
  measurements, from when to when, the lowest, the highest and the newest.
  Each chart has its values as a table in the same card, in a `<details>`
  that is closed at first. The axes and the layer of the points are
  `aria-hidden`, and no part of a chart takes the keyboard focus: the
  table is the way of the keyboard and of a screen reader. A chart never
  holds a value that the page says nowhere else.
- **One colour.** The series is `--accent`, the grid is `--border`, and
  the lines of the other members of a group are `--field` at a low
  opacity, behind the line of the member. A chart never uses the colour of
  a state. A change is an arrow and words ("45 g more than on 21 November
  2026"), with no colour of good or bad: a pup that gains is well, and so
  is a heavy dog that loses.
- **A series has one unit: the unit of its newest measurement.**
  `Rescord.Journal.Series` makes the series of a kind from the journal
  entries. A measurement in another unit is a point when
  `Rescord.Units.convert/3` converts it. One that does not convert is not
  a point: the card says how many are not in the chart, and the table has
  them as they were recorded. A value that Rescord converted is rounded to
  four significant digits for the page, and the table shows what was
  recorded beside it. ADR 0094 changed this later: a kind can name its
  standard unit, and the series of such a kind is in that unit. A kind
  with no standard unit keeps the unit of its newest measurement.
- **Three places show the measurements.**
  1. `/o/<short name>/residents/<id>/measurements`: a card for each kind
     with the newest value, its change, the chart, the point that the
     person chose, and the table. A time range (All, 1 year, 90 days,
     30 days) is in the address (`?range=90`). A person who can write to
     the journal records a measurement there, with the action `write` of
     the journal.
  2. `/o/<short name>/groups/<id>/measurements`: one kind (`?kind=<id>`)
     for each member, as small charts on one scale, with the line of the
     member in front of the lines of the others. The page says the scale
     once in words.
  3. The page of a resident: each newest value has a sparkline and the
     words of its change.
- **No table changes, no new action and no new power.**
  `Rescord.Journal.series/2` and `series_of/2` read the entries with the
  read action of the journal, as the person. A person who cannot read the
  journal of a resident sees no measurement.
- **With many points a chart does less.** With more than 40 points it
  draws the line and the newest dot alone. With more than 120 no point
  answers, and a shorter range gives them back.

## Consequences

- We own the chart code. A chart of another form, such as bars, is more of
  our own code and not a setting of a library.
- Each number of a chart goes through `RescordWeb.JournalWords.number/1`
  and each date through `RescordWeb.ResidentWords.date/1`, so a chart
  follows the locale of the organisation (ADR 0075) with no code of its
  own.
- One colour and a grey serve a group of any size. A chart with a colour
  for each member needs new tokens: a palette that a person with a colour
  vision deficiency can tell apart, in both schemes, and it stops at about
  eight members.
- The lines of the other members of a group are below the contrast of an
  edge on purpose. They are a background, the small chart is
  `aria-hidden`, and each tile says its value and its change in words.
- `Rescord.Journal.latest_measurements/2` stays for the dose calculator.
  The pages of the measurements do not use it.
- Not in this work: a reference range or a goal for a kind, a warning for
  a value that falls, a unit that an administrator sets for a kind, a rate
  of change, and a chart in a PDF report. Nobody has looked at the charts
  in Safari or in Firefox: the tools had Chromium alone, as for ADR 0061.
