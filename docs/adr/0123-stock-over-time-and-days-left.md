# ADR 0123: Stock over time, and the days left

Status: accepted. The seventh chart that is built of issue 36 (its chart
5), which the maintainer chose to build with the other nine on
28 November 2026 (ADR 0116).

## Context

A refuge asks when it will run out of each item. Rescord stores no level:
the level of an item is the sum of the movements of its lots. Issue 36
proposes, on the page of an item, the stock at the end of each day with a
forecast at the rate of the use of the last 30 days, the reorder level and
the expiry of each lot; and on the inventory, each item as a bar of its
days left, the soonest first.

## Decision

1. **The reads** are of `Rescord.Inventory`, as the actor, with `select`:
   `levels_by_day/4` sums the movements of one item to the end of each
   day in the time zone of the organisation, and gives what was used or
   discarded in the 30 days to the last day; `use_by_item/2` gives that
   use for each item. `days_left/2` is the whole days that a level lasts
   at that rate: `nil` with no use, `0` with no stock. Only stock that has
   not expired counts for the days left.
2. **The page of an item** has a section "Stock over time" below the forms
   that record a movement: a step line of the last 90 days, the forecast
   dashed to the day when the stock runs out or to 30 days ahead, the
   reorder level of the whole item as a rule, and a dotted line where a
   lot with stock expires in that time. The words say the level, the use,
   the day when it runs out and the lots that expire, and a table holds
   the level at the end of each week. `RescordWeb.StockTrend` builds it,
   and `InventoryComponents.stock_trend/1` draws it.
3. **`line_chart/1` gains `ahead` and `moments`**: points of a forecast,
   drawn dashed in the lead colour, and instants drawn as dotted lines.
4. **The days left of each item** are a page of insights, not a part of
   the inventory page: `RescordWeb.StockInsightsLive` at
   `/o/:organisation/insights/stock`. The inventory page is a collection
   of Cinder that a member works in, and a chart above it would push the
   list down. Each item with a use is a row of `timeline/1` on a scale of
   the next 90 days, from today to the day when it runs out, dashed when
   it lasts longer; the items with no use are named below. Each member
   can open it.

## Consequences

- A movement written later with an earlier time changes the past levels,
  which is right, and the page says nothing of it.
- An item with no use in 30 days has no rate, and both pages say so
  instead of a guess.
- The rate is flat: a refuge that uses more in winter sees the forecast of
  the last 30 days only.
