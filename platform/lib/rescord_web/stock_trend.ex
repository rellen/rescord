defmodule RescordWeb.StockTrend do
  @moduledoc """
  What the chart of the stock of an item shows (ADR 0123): the level at the
  end of each day, the forecast at the rate of the use of the last 30 days
  to the day when the stock runs out, the reorder level, and the expiry of
  each lot with stock in the time of the chart. Its words, and a table of
  the level at the end of each week.

  It is pure: `Rescord.Inventory.levels_by_day/4` and
  `Rescord.Inventory.item_stock/2` read.
  """

  alias Rescord.Inventory
  alias RescordWeb.{Chart, InventoryWords, Locale}

  # The days of the forecast, at most.
  @ahead 30

  @doc """
  The assigns of `RescordWeb.InventoryComponents.stock_trend/1` from the
  stock of an item, its levels of each day to `today`, and the use.
  """
  @spec build(map, %{levels: [{Date.t(), Decimal.t()}], used: Decimal.t()}, Date.t()) :: map
  def build(stock, %{levels: levels, used: used}, %Date{} = today) do
    item = stock.item
    usable = Decimal.sub(stock.level, stock.expired)
    days_left = Inventory.days_left(usable, used)
    ahead = ahead(usable, used, days_left, today)
    rules = if item.reorder_level, do: [item.reorder_level], else: []
    points = points(levels, item)
    {first, _} = hd(levels)
    last = if ahead == [], do: today, else: List.last(ahead).date

    expiring =
      for %{lot: %{expires_on: %Date{} = on} = lot, level: level} <- stock.lots,
          Decimal.gt?(level, 0),
          not Date.before?(on, first),
          not Date.after?(on, last),
          do: {lot, on}

    anchor = [%{at: noon(first), value: Decimal.new(0)}]
    rule_points = Enum.map(rules, &%{at: noon(first), value: &1})

    %{
      points: points,
      ahead: Enum.map(ahead, &Map.delete(&1, :date)),
      rules: rules,
      moments: Enum.map(expiring, fn {_, on} -> DateTime.new!(on, ~T[00:00:00]) end),
      scale: Chart.scale(points ++ ahead ++ rule_points ++ anchor),
      from: Locale.date(first),
      to: Locale.date(last),
      summary: summary(item, usable, used, days_left, today, expiring),
      weeks: weeks(levels)
    }
  end

  defp noon(date), do: DateTime.new!(date, ~T[12:00:00])

  defp points(levels, item) do
    for {date, level} <- levels do
      %{
        id: Date.to_iso8601(date),
        at: noon(date),
        value: level,
        label: "#{Locale.date(date)}: #{InventoryWords.quantity(level, item)}"
      }
    end
  end

  # The line from today to the day when the stock runs out, or to the last
  # day of the forecast when it lasts longer.
  defp ahead(_usable, _used, nil, _today), do: []
  defp ahead(_usable, _used, 0, _today), do: []

  defp ahead(usable, used, days_left, today) do
    days = min(days_left, @ahead)
    gone = used |> Decimal.mult(days) |> Decimal.div(Inventory.use_days())
    level = Decimal.max(Decimal.sub(usable, gone), Decimal.new(0))
    to = Date.add(today, days)

    [
      %{id: "now", date: today, at: noon(today), value: usable},
      %{id: "then", date: to, at: noon(to), value: level}
    ]
  end

  defp summary(item, usable, used, days_left, today, expiring) do
    level = "#{InventoryWords.quantity(usable, item)} in stock that has not expired."

    use =
      case days_left do
        nil ->
          " Nothing was used or discarded in the last #{Inventory.use_days()} days, so the " <>
            "page cannot say when it runs out."

        0 ->
          ""

        days ->
          " In the last #{Inventory.use_days()} days, members used or discarded " <>
            "#{InventoryWords.quantity(used, item)}, so it lasts about " <>
            "#{Locale.count(days, "more day", "more days")}, to #{Locale.date(Date.add(today, days))}."
      end

    reorder =
      if item.reorder_level,
        do: " The reorder level is #{InventoryWords.quantity(item.reorder_level, item)}.",
        else: ""

    expiry =
      case expiring do
        [] ->
          ""

        lots ->
          words =
            Enum.map(lots, fn {lot, on} -> "#{lot.code || "a lot"} on #{Locale.date(on)}" end)

          " A lot with stock expires in this time: #{Locale.list(words)}."
      end

    level <> use <> reorder <> expiry
  end

  # The level at the end of each week, the newest first.
  defp weeks(levels) do
    levels
    |> Enum.filter(fn {date, _} -> Date.day_of_week(date) == 7 end)
    |> Enum.concat([List.last(levels)])
    |> Enum.uniq()
    |> Enum.reverse()
  end
end
