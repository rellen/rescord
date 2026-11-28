defmodule RescordWeb.ReportWords.Movements do
  @moduledoc "The words of the arrivals and the departures of a period (`Rescord.Reports.Facts.Movements`)."

  import RescordWeb.ReportWords

  alias RescordWeb.{ResidentWords, TaskWords}

  def data(facts) do
    %{
      frame:
        frame(
          facts,
          "Arrivals and departures",
          "From #{ResidentWords.date(facts.from)} to #{ResidentWords.date(facts.to)}"
        ),
      summary: [
        %{label: "In care at the start", value: amount(facts.at_start)},
        %{label: "Arrivals", value: amount(length(facts.arrived))},
        %{label: "Departures", value: amount(length(facts.left))},
        %{label: "In care at the end", value: amount(facts.at_end)}
      ],
      arrivals_by_kind: tally(facts.arrived, &ResidentWords.arrival(&1.arrival.kind)),
      arrivals_by_species: tally(facts.arrived, &species/1),
      departures_by_kind: tally(facts.left, &ResidentWords.departure(&1.departure.kind)),
      departures_by_species: tally(facts.left, &species/1),
      arrivals: Enum.map(facts.arrived, &arrival/1),
      departures: Enum.map(facts.left, &departure/1)
    }
  end

  defp arrival(resident) do
    %{
      date: ResidentWords.date(resident.arrival.arrived_on),
      name: name(resident),
      species: species(resident),
      kind: ResidentWords.arrival(resident.arrival.kind),
      note: text(resident.arrival.note)
    }
  end

  defp departure(resident) do
    %{
      date: ResidentWords.date(resident.departure.departed_on),
      name: name(resident),
      species: species(resident),
      kind: ResidentWords.departure(resident.departure.kind),
      stay: stay(resident),
      note: text(resident.departure.note)
    }
  end

  # The days from the arrival to the departure, or `nil` with no arrival.
  defp stay(%{arrival: %{arrived_on: from}, departure: %{departed_on: to}}),
    do: TaskWords.days(max(Date.diff(to, from), 0))

  defp stay(_resident), do: nil

  defp species(resident), do: text(resident.species_label) || "No species"

  # How many residents have each word, the most first.
  defp tally(residents, word) do
    residents
    |> Enum.frequencies_by(word)
    |> Enum.sort_by(fn {label, number} -> {-number, label} end)
    |> Enum.map(fn {label, number} -> %{label: label, value: amount(number)} end)
  end
end
