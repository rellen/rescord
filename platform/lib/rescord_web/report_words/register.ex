defmodule RescordWeb.ReportWords.Register do
  @moduledoc "The words of the register of the residents (`Rescord.Reports.Facts.Register`)."

  import RescordWeb.ReportWords

  alias RescordWeb.ResidentWords

  def data(facts) do
    rows = Enum.map(facts.rows, &row(&1, facts.on))

    %{
      frame:
        frame(
          facts,
          "Register of residents",
          if(facts.on == facts.today,
            do: "The residents in care today, #{ResidentWords.date(facts.on)}",
            else: "The residents in care at the end of #{ResidentWords.date(facts.on)}"
          )
        ),
      counts: counts(rows),
      rows: rows
    }
  end

  defp row(%{resident: resident, away?: away?, homes: homes}, on) do
    %{
      name: name(resident),
      species: text(resident.species_label),
      breed: labels(resident.resident_breeds, :breed),
      sex: sex(resident),
      born: born(resident, on),
      identifiers: Enum.map(identifiers(resident), &"#{&1.kind}: #{&1.value}"),
      arrived:
        "#{ResidentWords.date(resident.arrival.arrived_on)}, " <>
          String.downcase(ResidentWords.arrival(resident.arrival.kind)),
      place: homes(homes),
      status: ResidentWords.status(if(away?, do: :away, else: :in_care))
    }
  end

  defp sex(resident) do
    case resident.desex_status do
      status when status in [:entire, :desexed] ->
        "#{ResidentWords.sex(resident.sex)}, #{String.downcase(ResidentWords.desex(status))}"

      _unknown ->
        ResidentWords.sex(resident.sex)
    end
  end

  # The number of residents, then the number of each species, the largest first.
  defp counts(rows) do
    species =
      rows
      |> Enum.frequencies_by(&(&1.species || "No species"))
      |> Enum.sort_by(fn {species, number} -> {-number, species} end)
      |> Enum.map(fn {species, number} -> %{label: species, value: amount(number)} end)

    away = Enum.count(rows, &(&1.status == ResidentWords.status(:away)))

    [%{label: "Residents", value: amount(length(rows))}] ++
      species ++
      if(away > 0,
        do: [%{label: ResidentWords.status(:away), value: amount(away)}],
        else: []
      )
  end
end
