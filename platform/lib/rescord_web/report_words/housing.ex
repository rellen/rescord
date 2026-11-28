defmodule RescordWeb.ReportWords.Housing do
  @moduledoc "The words of the housing report (`Rescord.Reports.Facts.Housing`)."

  import RescordWeb.ReportWords

  alias Rescord.{Locations, Residents}
  alias RescordWeb.ResidentWords

  def data(facts) do
    rows = for {node, depth} <- Locations.flat(facts.tree), do: row(node, depth)
    housed = facts.tree |> Enum.map(& &1.count) |> Enum.sum()

    %{
      frame: frame(facts, "Housing", "Who lives where on #{ResidentWords.date(facts.today)}"),
      total:
        "#{count(housed, "resident", "residents")} in " <>
          count(length(rows), "location", "locations"),
      rows: rows,
      unplaced: Enum.map(facts.unplaced, &name/1)
    }
  end

  defp row(node, depth) do
    location = node.location

    %{
      depth: depth,
      name: location.name,
      kind: label(location.kind),
      count:
        case location.capacity do
          nil -> amount(node.count)
          capacity -> "#{amount(node.count)} of #{amount(capacity)}"
        end,
      over: node.over?,
      residents: Enum.map(node.residents, &name(&1.resident)),
      groups:
        for {_placement, group, members} <- node.groups do
          %{
            name: Residents.group_name(group),
            members: Enum.map(members, &name(&1.resident))
          }
        end
    }
  end
end
