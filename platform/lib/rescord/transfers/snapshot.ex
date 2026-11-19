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
      with its kind, its time, its note and its facts;
    * `"journal"` - with the part `:journal`: each other entry;
    * `"stay"` - with the part `:stay`: the arrival, the absence and the
      departure;
    * `"placements"` - with the part `:placements`: each change of the
      placement of the resident, with the name of the location;
    * `"relations"` - with the part `:relations`: the parents, the young,
      the families and the groups, by name.

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
  @spec build(String.t(), [atom], keyword) :: {:ok, map} | :error
  def build(resident_id, parts, opts) do
    with {:ok, %{} = resident} <- Residents.resident_with_facts(resident_id, opts),
         {:ok, entries} <- Journal.entries(resident_id, opts) do
      {medical, other} = Enum.split_with(entries, &Journal.medical?(&1.kind))

      copy =
        %{
          "facts" => facts(resident),
          "medical" => Enum.map(medical, &entry/1),
          "taken_at" => DateTime.to_iso8601(DateTime.utc_now())
        }
        |> put_part(:journal in parts, "journal", fn -> Enum.map(other, &entry/1) end)
        |> put_part(:stay in parts, "stay", fn -> stay(resident) end)
        |> put_part(:placements in parts, "placements", fn -> placements(resident_id, opts) end)
        |> put_part(:relations in parts, "relations", fn -> relations(resident_id, opts) end)

      {:ok, copy}
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

  defp entry(entry) do
    %{
      "kind" => text(entry.kind),
      "at" => DateTime.to_iso8601(entry.happened_at),
      "note" => entry.note,
      "facts" => entry_facts(entry)
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
end
