defmodule RescordWeb.ReportWords.Stock do
  @moduledoc "The words of the stock report (`Rescord.Reports.Facts.Stock`)."

  import RescordWeb.ReportWords

  alias Rescord.Inventory
  alias RescordWeb.{InventoryWords, ResidentWords}

  def data(facts) do
    %{
      frame:
        frame(facts, "Stock", "The stock of each item on #{ResidentWords.date(facts.today)}"),
      attention:
        for stock <- facts.stock, fault <- Inventory.faults(stock) do
          %{
            item: stock.item.name,
            words: fault |> InventoryWords.fault() |> elem(0),
            detail: detail(fault, stock, facts.paths)
          }
        end,
      categories:
        facts.stock
        |> Enum.group_by(&(label(&1.item.category) || "No category"))
        |> Enum.sort_by(fn {category, _items} -> category end)
        |> Enum.map(fn {category, items} ->
          %{name: category, items: Enum.map(items, &item(&1, facts.paths))}
        end)
    }
  end

  defp item(stock, paths) do
    %{
      name: stock.item.name,
      level: InventoryWords.quantity(stock.level, stock.item),
      reorder:
        stock.item.reorder_level && InventoryWords.quantity(stock.item.reorder_level, stock.item),
      states: stock |> InventoryWords.states() |> Enum.map_join(", ", &elem(&1, 0)),
      note: text(stock.item.note),
      lots: Enum.map(stock.lots, &lot(&1, stock.item, paths))
    }
  end

  defp lot(lot_stock, item, paths) do
    %{
      name: InventoryWords.lot(lot_stock.lot),
      expires:
        case lot_stock.lot.expires_on do
          nil -> InventoryWords.expiry(:none)
          date -> ResidentWords.date(date)
        end,
      # `In date` is what a person expects: only the other states have words.
      state:
        if(lot_stock.expiry in [:expired, :soon],
          do: InventoryWords.expiry(lot_stock.expiry),
          else: nil
        ),
      level: InventoryWords.quantity(lot_stock.level, item),
      places:
        for {place, level} <- lot_stock.places do
          %{place: place(place, paths), level: InventoryWords.quantity(level, item)}
        end
    }
  end

  defp detail(:below_zero, stock, paths) do
    Enum.map_join(stock.below_zero, "; ", fn {lot, place, level} ->
      "#{InventoryWords.lot(lot)}, #{place(place, paths)}: the record has " <>
        InventoryWords.quantity(level, stock.item)
    end)
  end

  defp detail(:short, stock, paths) do
    Enum.map_join(stock.short, "; ", fn short ->
      where = if short.location_id, do: " in #{place(short.location_id, paths)}", else: ""

      "#{InventoryWords.quantity(short.level, stock.item)} in date#{where}, " <>
        "the reorder level is #{InventoryWords.quantity(short.wanted, stock.item)}"
    end)
  end

  defp detail(:expired, stock, _paths),
    do: "#{InventoryWords.quantity(stock.expired, stock.item)} is past its expiry date"

  defp detail(:soon, stock, _paths),
    do: "#{InventoryWords.quantity(stock.soon, stock.item)} expires soon"

  defp place(nil, _paths), do: "No place in particular"

  defp place(id, paths) do
    case Map.get(paths, id) do
      nil -> "A location that is not here now"
      names -> path(names)
    end
  end
end
