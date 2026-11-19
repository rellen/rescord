defmodule Rescord.Transfers.Snapshot do
  @moduledoc """
  The copy of a resident that a transfer holds (ADR 0042): plain data, with
  text keys, that does not change after the transfer.

  `build/3` reads the resident in the schema of the refuge that sends it,
  with the options of the caller, and returns a map:

    * `"facts"` - always: the name, the species, the sex, the date of
      birth, the desex status, the size class, the coat, the breeds, the
      colours, the temperaments, the identifiers, the arrival date and the
      status;
    * `"medical"` - always: each entry of a medical kind, the newest first,
      with its kind, its time, its note, its facts and its files (ADR 0043);
    * `"journal"` - with the part `:journal`: each other entry;
    * `"stay"` - with the part `:stay`: the arrival, the absence and the
      departure;
    * `"placements"` - with the part `:placements`: each change of the
      placement of the resident, with the name of the location;
    * `"relations"` - with the part `:relations`: the parents, the young,
      the families and the groups, by name.

  `build/3` also returns the source of each file: its id, its key in the
  store, and its type. The copy names no key.

  `clean/1` rebuilds a copy that came from another server, with the keys
  and the types of values above alone, so a page that shows it meets
  nothing that it does not know.

  A date is ISO 8601 text, an instant is ISO 8601 text in UTC, a number is
  text, and a value of a list is its label. The copy names no id of the
  refuge that sends it, other than in the record of the transfer.
  """

  alias Rescord.{Journal, Locations, Residents}

  @parts [:journal, :stay, :placements, :relations]

  @doc "The parts that a sender can add to the facts and the medical history."
  @spec parts() :: [atom]
  def parts, do: @parts

  @doc """
  The copy of a resident with the parts `parts`, or `:error` when the
  options can read no such resident.
  """
  @spec build(String.t(), [atom], keyword) :: {:ok, map, [map]} | :error
  def build(resident_id, parts, opts) do
    with {:ok, %{} = resident} <- Residents.resident_with_facts(resident_id, opts),
         {:ok, entries} <- Journal.entries(resident_id, opts) do
      {medical, other} = Enum.split_with(entries, &Journal.medical?(&1.kind))
      included = if :journal in parts, do: entries, else: medical
      {:ok, files_of} = Journal.attachments_of(Enum.map(included, & &1.id), opts)
      entry = &entry(&1, Map.get(files_of, &1.id, []))

      copy =
        %{
          "facts" => facts(resident),
          "medical" => Enum.map(medical, entry),
          "taken_at" => DateTime.to_iso8601(DateTime.utc_now())
        }
        |> put_part(:journal in parts, "journal", fn -> Enum.map(other, entry) end)
        |> put_part(:stay in parts, "stay", fn -> stay(resident) end)
        |> put_part(:placements in parts, "placements", fn -> placements(resident_id, opts) end)
        |> put_part(:relations in parts, "relations", fn -> relations(resident_id, opts) end)

      sources =
        for {_entry_id, attachments} <- files_of, attachment <- attachments do
          %{
            "id" => attachment.id,
            "key" => attachment.key,
            "content_type" => attachment.content_type
          }
        end

      {:ok, copy, sources}
    else
      _no_resident -> :error
    end
  end

  defp put_part(copy, true, key, value), do: Map.put(copy, key, value.())
  defp put_part(copy, false, _key, _value), do: copy

  defp facts(resident) do
    %{
      "name" => resident.name,
      "species" => label(resident.species),
      "sex" => text(resident.sex),
      "born_on" => date(resident.born_on),
      "born_on_estimated" => resident.born_on_estimated,
      "desex_status" => text(resident.desex_status),
      "size_class" => label(resident.size_class),
      "coat" => label(resident.coat),
      "breeds" => Enum.map(resident.resident_breeds, &label(&1.breed)),
      "colours" => Enum.map(resident.resident_colours, &label(&1.colour)),
      "temperaments" => Enum.map(resident.resident_temperaments, &label(&1.temperament)),
      "identifiers" =>
        Enum.map(resident.identifiers, &%{"kind" => label(&1.kind), "value" => &1.value}),
      "arrived_on" => date(resident.arrival && resident.arrival.arrived_on),
      "status" => text(resident.status)
    }
  end

  defp entry(entry, attachments) do
    %{
      "kind" => text(entry.kind),
      "at" => DateTime.to_iso8601(entry.happened_at),
      "note" => entry.note,
      "facts" => entry_facts(entry),
      "files" =>
        Enum.map(
          attachments,
          &%{
            "id" => &1.id,
            "name" => &1.name,
            "content_type" => &1.content_type,
            "size" => &1.size
          }
        )
    }
  end

  defp entry_facts(%{measurement: %{} = m}) do
    %{
      "measure_kind" => label(m.measure_kind),
      "value" => m.value && Decimal.to_string(Decimal.normalize(m.value), :normal),
      "unit" => label(m.unit)
    }
  end

  defp entry_facts(%{diagnosis: %{} = d}), do: %{"condition" => label(d.condition)}
  defp entry_facts(%{procedure: %{} = p}), do: %{"procedure" => label(p.procedure_kind)}
  defp entry_facts(%{vaccination: %{} = v}), do: %{"vaccine" => v.vaccine}

  defp entry_facts(%{prescription: %{} = p}) do
    %{
      "medication" => p.medication,
      "dose" => p.dose,
      "route" => text(p.route),
      "starts_on" => date(p.starts_on),
      "ends_on" => date(p.ends_on)
    }
  end

  defp entry_facts(%{dose: %{} = d}) do
    medication = if match?(%{medication: _}, d.prescription), do: d.prescription.medication
    %{"medication" => medication, "amount" => d.amount}
  end

  defp entry_facts(_entry), do: %{}

  defp stay(resident) do
    %{
      "arrival" =>
        resident.arrival &&
          %{
            "kind" => text(resident.arrival.kind),
            "on" => date(resident.arrival.arrived_on),
            "note" => resident.arrival.note
          },
      "absence" =>
        resident.absence &&
          %{
            "reason" => resident.absence.reason,
            "expected_back_on" => date(resident.absence.expected_back_on)
          },
      "departure" =>
        resident.departure &&
          %{
            "kind" => text(resident.departure.kind),
            "on" => date(resident.departure.departed_on),
            "note" => resident.departure.note
          }
    }
  end

  defp placements(resident_id, opts) do
    {:ok, tree} = Locations.tree(opts)

    names =
      Map.new(Locations.flat(tree), fn {node, _depth} ->
        {node.location.id, node.location.name}
      end)

    for change <- Locations.changes(resident_id, opts) do
      %{
        "at" => DateTime.to_iso8601(change.at),
        "kind" => text(change.kind),
        "location" => Map.get(names, change.record.location_id, "A location that is closed")
      }
    end
  end

  defp relations(resident_id, opts) do
    case Residents.relations(resident_id, opts) do
      nil ->
        %{}

      relations ->
        %{
          "parents" =>
            Enum.map(relations.parents, &%{"role" => text(&1.role), "name" => &1.parent.name}),
          "young" => Enum.map(relations.young, & &1.resident.name),
          "families" => Enum.map(relations.families, & &1.family.name),
          "groups" =>
            Enum.map(relations.groups, fn {_membership, group} -> Residents.group_name(group) end)
        }
    end
  end

  defp label(%{label: label}), do: to_string(label)
  defp label(_none), do: nil

  defp date(%Date{} = date), do: Date.to_iso8601(date)
  defp date(_none), do: nil

  defp text(nil), do: nil
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value), do: to_string(value)

  @doc """
  A copy from another server, rebuilt with the keys and the types of
  `build/3` alone: text, a date or an instant that parses, a boolean, or a
  list of those. Each other value is dropped. Returns `:error` for a value
  that is not a map with facts.
  """
  @spec clean(term) :: {:ok, map} | :error
  def clean(%{"facts" => %{} = facts} = copy) do
    cleaned =
      %{
        "facts" => clean_facts(facts),
        "medical" => clean_list(copy["medical"], &clean_entry/1),
        "taken_at" => instant(copy["taken_at"])
      }
      |> maybe("journal", copy, &clean_list(&1, fn entry -> clean_entry(entry) end))
      |> maybe("stay", copy, &clean_stay/1)
      |> maybe(
        "placements",
        copy,
        &clean_list(&1, fn p -> pick(p, ~w(kind location), at: ["at"]) end)
      )
      |> maybe("relations", copy, &clean_relations/1)

    {:ok, cleaned}
  end

  def clean(_other), do: :error

  defp clean_facts(facts) do
    facts
    |> pick(~w(name species sex desex_status size_class coat status),
      dates: ~w(born_on arrived_on)
    )
    |> Map.merge(%{
      "born_on_estimated" => facts["born_on_estimated"] == true,
      "breeds" => strings(facts["breeds"]),
      "colours" => strings(facts["colours"]),
      "temperaments" => strings(facts["temperaments"]),
      "identifiers" => clean_list(facts["identifiers"], &pick(&1, ~w(kind value)))
    })
  end

  defp clean_entry(%{} = entry) do
    entry
    |> pick(~w(kind note), at: ["at"])
    |> Map.put(
      "facts",
      pick(
        if(is_map(entry["facts"]), do: entry["facts"], else: %{}),
        ~w(measure_kind value unit condition procedure vaccine medication dose route amount),
        dates: ~w(starts_on ends_on)
      )
    )
    |> Map.put("files", clean_list(entry["files"], &clean_file/1))
  end

  defp clean_entry(_other), do: nil

  defp clean_file(%{"id" => id, "size" => size} = file) when is_integer(size) and size >= 0 do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> file |> pick(~w(name content_type)) |> Map.merge(%{"id" => id, "size" => size})
      :error -> nil
    end
  end

  defp clean_file(_other), do: nil

  defp clean_stay(%{} = stay) do
    for key <- ~w(arrival absence departure), into: %{} do
      value =
        case stay[key] do
          %{} = part -> pick(part, ~w(kind note reason), dates: ~w(on expected_back_on))
          _none -> nil
        end

      {key, value}
    end
  end

  defp clean_stay(_other), do: nil

  defp clean_relations(%{} = relations) do
    %{
      "parents" => clean_list(relations["parents"], &pick(&1, ~w(role name))),
      "young" => strings(relations["young"]),
      "families" => strings(relations["families"]),
      "groups" => strings(relations["groups"])
    }
  end

  defp clean_relations(_other), do: nil

  defp maybe(cleaned, key, copy, clean) do
    if Map.has_key?(copy, key), do: Map.put(cleaned, key, clean.(copy[key])), else: cleaned
  end

  defp clean_list(list, clean) when is_list(list),
    do: list |> Enum.take(5000) |> Enum.map(clean) |> Enum.reject(&is_nil/1)

  defp clean_list(_other, _clean), do: []

  # The text values of `keys`, the dates of `:dates` and the instants of
  # `:at`, each when it has the right type, and else `nil`.
  defp pick(map, keys, opts \\ [])

  defp pick(%{} = map, keys, opts) do
    texts = Map.new(keys, &{&1, string(map[&1])})
    dates = Map.new(Keyword.get(opts, :dates, []), &{&1, date_text(map[&1])})
    instants = Map.new(Keyword.get(opts, :at, []), &{&1, instant(map[&1])})
    texts |> Map.merge(dates) |> Map.merge(instants)
  end

  defp pick(_other, _keys, _opts), do: nil

  defp string(text) when is_binary(text), do: String.slice(text, 0, 2000)
  defp string(_other), do: nil

  defp strings(list) when is_list(list), do: list |> Enum.map(&string/1) |> Enum.reject(&is_nil/1)
  defp strings(_other), do: []

  defp date_text(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, _date} -> text
      _bad -> nil
    end
  end

  defp date_text(_other), do: nil

  defp instant(text) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, _instant, _offset} -> text
      _bad -> nil
    end
  end

  defp instant(_other), do: nil
end
