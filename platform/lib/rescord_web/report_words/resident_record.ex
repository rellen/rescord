defmodule RescordWeb.ReportWords.ResidentRecord do
  @moduledoc "The words of the record of a resident (`Rescord.Reports.Facts.ResidentRecord`)."

  import RescordWeb.ReportWords

  alias Rescord.{Accounts, Residents}
  alias RescordWeb.{JournalWords, ResidentWords}

  def data(facts) do
    resident = facts.resident

    %{
      frame: frame(facts, "Record of #{named(resident)}", subtitle(facts.journal, facts.photos)),
      name: name(resident),
      status: ResidentWords.status(resident.status),
      photo: facts.profile,
      about: about(resident, facts.today),
      identifiers: identifiers(resident),
      stay: stay(resident, facts.homes),
      relations: relations(facts.relations),
      measurements: Enum.map(facts.measurements, &measurement(&1, facts.organisation)),
      journal: journal(facts),
      photos:
        for photo <- facts.photos do
          %{
            file: photo.file,
            caption: text(photo.caption),
            date: ResidentWords.date(photo.taken_on)
          }
        end,
      more_photos: more(facts.more_photos)
    }
  end

  defp subtitle(journal, photos) do
    parts =
      case journal do
        :all -> ["its journal"]
        :none -> []
        _medical -> ["its medical history"]
      end ++ if(photos == [], do: [], else: ["its photos"])

    if parts == [], do: nil, else: "With " <> Enum.join(parts, " and ")
  end

  @doc "The facts of a resident, each as a label and a value: only the ones that are recorded."
  def about(resident, today) do
    rows([
      {"Species", label(resident.species)},
      {"Breed", labels(resident.resident_breeds, :breed)},
      {"Sex", ResidentWords.sex(resident.sex)},
      {"Desex status", ResidentWords.desex(resident.desex_status || :unknown)},
      {"Born", born(resident, today)},
      {"Colour", labels(resident.resident_colours, :colour)},
      {"Size class", label(resident.size_class)},
      {"Coat", label(resident.coat)},
      {"Temperament", labels(resident.resident_temperaments, :temperament)}
    ])
  end

  defp stay(resident, homes) do
    arrival =
      case resident.arrival do
        nil ->
          []

        arrival ->
          [
            {"Arrival",
             "#{ResidentWords.arrival(arrival.kind)}, #{ResidentWords.date(arrival.arrived_on)}"},
            {"Note about the arrival", arrival.note}
          ]
      end

    absence =
      case resident.absence do
        nil ->
          []

        absence ->
          [
            {"Away", absence.reason},
            {"Expected back", ResidentWords.date(absence.expected_back_on)}
          ]
      end

    departure =
      case resident.departure do
        nil ->
          []

        departure ->
          [
            {"Departure",
             "#{ResidentWords.departure(departure.kind)}, " <>
               ResidentWords.date(departure.departed_on)},
            {"Note about the departure", departure.note}
          ]
      end

    rows([{"Lives in", homes(homes)}] ++ arrival ++ absence ++ departure)
  end

  defp relations(nil), do: []

  defp relations(relations) do
    parents =
      for link <- relations.parents, do: {ResidentWords.kin(link.role), name(link.parent)}

    young =
      case relations.young do
        [] -> []
        links -> [{"Young", Enum.map_join(links, ", ", &name(&1.resident))}]
      end

    families =
      case relations.families do
        [] -> []
        memberships -> [{"Family", Enum.map_join(memberships, ", ", & &1.family.name)}]
      end

    groups =
      for {_membership, group} <- relations.groups do
        words = Residents.words(group)
        {"Group", Residents.group_name(group) <> if(words, do: " (#{words})", else: "")}
      end

    rows(parents ++ young ++ families ++ groups)
  end

  defp measurement(entry, organisation) do
    %{
      words: JournalWords.facts(entry),
      date: entry.happened_at |> local(organisation) |> DateTime.to_date() |> ResidentWords.date()
    }
  end

  defp journal(%{journal: :none}), do: nil

  defp journal(facts) do
    %{
      title: if(facts.journal == :all, do: "Journal", else: "Medical history"),
      empty:
        if(facts.journal == :all,
          do: "The journal has no entry.",
          else: "The journal has no medical entry."
        ),
      entries: Enum.map(facts.entries, &entry(&1, facts.organisation))
    }
  end

  defp entry(%{entry: entry, files: files}, organisation) do
    %{
      date: JournalWords.time(local(entry.happened_at, organisation)),
      kind: JournalWords.kind(entry.kind),
      facts: text(JournalWords.facts(entry)),
      note: text(entry.note),
      follows:
        case entry.follows do
          %{happened_at: at} ->
            "Adds to the entry of #{JournalWords.time(local(at, organisation))}."

          _none ->
            nil
        end,
      files:
        if(files > 0,
          do: "#{count(files, "file", "files")} with this entry in Rescord.",
          else: nil
        )
    }
  end

  defp more(0), do: nil
  defp more(number), do: "#{count(number, "more photo is", "more photos are")} in Rescord."

  defp local(instant, organisation), do: Accounts.local_time(organisation, instant)
end
