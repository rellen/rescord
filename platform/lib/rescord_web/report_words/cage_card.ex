defmodule RescordWeb.ReportWords.CageCard do
  @moduledoc "The words of the cage card of a resident (`Rescord.Reports.Facts.CageCard`)."

  import RescordWeb.ReportWords

  alias RescordWeb.{JournalWords, ResidentWords, TaskWords}

  def data(facts) do
    resident = facts.resident

    %{
      frame: frame(facts, "Cage card of #{named(resident)}"),
      name: name(resident),
      status: ResidentWords.status(resident.status),
      photo: facts.profile,
      species: label(resident.species),
      about:
        rows([
          {"Breed", labels(resident.resident_breeds, :breed)},
          {"Sex", sex(resident)},
          {"Age", ResidentWords.age(resident.born_on, facts.today)},
          {"Colour", labels(resident.resident_colours, :colour)},
          {"Markings", resident.markings},
          {"Temperament", labels(resident.resident_temperaments, :temperament)},
          {"Lives in", homes(facts.homes)},
          {"Arrived", resident.arrival && ResidentWords.date(resident.arrival.arrived_on)}
        ]),
      away: away(resident.absence),
      identifiers: identifiers(resident),
      measurements: for(entry <- facts.measurements, do: JournalWords.facts(entry)),
      routines: Enum.map(facts.routines, &routine/1)
    }
  end

  # The sex with the desex status, when that is known: `Male, desexed`.
  defp sex(resident) do
    case resident.desex_status do
      status when status in [:entire, :desexed] ->
        "#{ResidentWords.sex(resident.sex)}, #{String.downcase(ResidentWords.desex(status))}"

      _unknown ->
        ResidentWords.sex(resident.sex)
    end
  end

  defp away(nil), do: nil

  defp away(absence) do
    back =
      if absence.expected_back_on,
        do: ", expected back on #{ResidentWords.date(absence.expected_back_on)}",
        else: ""

    "Away: #{absence.reason}#{back}"
  end

  defp routine(routine) do
    times = if routine.times == [], do: "", else: " at #{TaskWords.times(routine.times)}"

    %{
      title: routine.title,
      when: TaskWords.pattern(routine) <> times,
      note: text(routine.note)
    }
  end
end
