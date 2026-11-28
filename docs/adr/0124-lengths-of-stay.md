# ADR 0124: Lengths of stay

Status: accepted. The eighth chart that is built of issue 36 (its chart
8), which the maintainer chose to build with the other nine on
28 November 2026 (ADR 0116).

## Context

A refuge asks how long its residents stay, and whether that depends on how
they came. An average of the stays that ended says too little: the
residents still in care are left out, and they are often the long stays.
Issue 36 proposes a curve of the share still in care against the days
since the arrival, for each way of arrival, by the method of Kaplan and
Meier, which counts a stay that goes on up to today and then leaves it
out without a departure.

## Decision

1. **`Rescord.Residents.Survival`** is pure: from stays as
   `{days, ended?}` it makes the curve, a share at the start and at each
   day on which a stay ended, and the first day by which the share was at
   most a part, such as a half. It calculates with exact fractions of
   integers and makes a `Decimal` of four places only at the end, so a
   half is a half and no float is used. `Rescord.Residents` delegates to
   it (`stay_curve/1`, `stay_day_when/2`); the stays come from
   `Rescord.Residents.stays/1`, as for the census (ADR 0118).
2. **`RescordWeb.LengthsInsightsLive`** at
   `/o/:organisation/insights/lengths` has a section for each way of
   arrival, in the order of the list of words, with a step line of the
   share in percent from day 0 to the longest stay of the drawn groups.
   All lines share one scale from 0 to 100 percent, with a rule at 50.
   A way of arrival with fewer than 10 stays has no line, only its count:
   a curve of a few stays says more than it knows. A day is placed on the
   time scale of `line_chart/1` as an instant after a fixed epoch, so the
   chart needs no new kind of scale.
3. **Two tables give the values**: the days by which a quarter, a half and
   three quarters of each group had left ("Not yet" when the curve never
   came that low), with the count and those in care now; and the stays of
   each way of arrival by how they ended.
4. Each member can open the page: it reads the residents as that member.

## Consequences

- No confidence band: the page says how many stays each line has, and
  draws no line under 10. A band needs a decision on how to draw and word
  it.
- A resident has one stay, from its arrival to its departure, as in the
  census (ADR 0118).
- A stay of a resident who arrives later than today is left out.
