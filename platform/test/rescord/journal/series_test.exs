defmodule Rescord.Journal.SeriesTest do
  @moduledoc """
  Holds the rules of a series of measurements (ADR 0080): the unit of a
  series, what converts and what does not, the change of each point, and
  the time range. The entries here are plain maps, with the fields that
  `Rescord.Journal` loads: the module reads no database.
  """

  use ExUnit.Case, async: true

  alias Rescord.Journal.Series

  @weight "kind-weight"
  @temperature "kind-temperature"

  # An entry of a measurement, as `Rescord.Journal.series_of/2` loads one.
  defp entry(id, at, value, unit, extra \\ []) do
    kind_id = Keyword.get(extra, :kind, @weight)

    %{
      id: id,
      happened_at: at,
      note: Keyword.get(extra, :note),
      measurement: %{
        value: Decimal.new(value),
        measure_kind_id: kind_id,
        measure_kind: %{label: Keyword.get(extra, :label, "Weight")},
        unit_id: unit && "unit-" <> unit,
        unit: unit && %{label: unit}
      }
    }
  end

  defp values(points), do: Enum.map(points, &Decimal.to_string(&1.value, :normal))

  defp changes(points),
    do: Enum.map(points, &(&1.change && Decimal.to_string(&1.change, :normal)))

  test "a series has the points of one kind in the order of time" do
    [series] =
      Series.from_entries([
        entry("c", ~U[2026-11-14 08:00:00Z], "760", "g"),
        entry("a", ~U[2026-11-05 08:00:00Z], "690", "g"),
        entry("b", ~U[2026-11-09 08:00:00Z], "672", "g", note: "Off her food")
      ])

    assert series.kind_id == @weight
    assert series.label == "Weight"
    assert series.unit_label == "g"
    assert series.unit.code == "g"
    assert Enum.map(series.points, & &1.entry_id) == ["a", "b", "c"]
    assert values(series.points) == ["690", "672", "760"]
    assert Enum.at(series.points, 1).note == "Off her food"
    assert series.others == []
    assert Series.newest(series).entry_id == "c"
  end

  test "the series are one for each kind, in the order of the names" do
    series =
      Series.from_entries([
        entry("a", ~U[2026-11-05 08:00:00Z], "690", "g"),
        entry("b", ~U[2026-11-05 08:05:00Z], "38.5", "°C",
          kind: @temperature,
          label: "temperature"
        ),
        %{
          id: "c",
          happened_at: ~U[2026-11-05 09:00:00Z],
          note: "No measurement",
          measurement: nil
        }
      ])

    assert Enum.map(series, & &1.label) == ["temperature", "Weight"]
  end

  test "each point has its change from the point before, and the first has none" do
    [series] =
      Series.from_entries([
        entry("a", ~U[2026-11-05 08:00:00Z], "690", "g"),
        entry("b", ~U[2026-11-09 08:00:00Z], "672", "g"),
        entry("c", ~U[2026-11-14 08:00:00Z], "760", "g"),
        entry("d", ~U[2026-11-21 08:00:00Z], "760", "g")
      ])

    assert changes(series.points) == [nil, "-18", "88", "0"]

    assert Enum.map(series.points, & &1.before) ==
             [nil, ~U[2026-11-05 08:00:00Z], ~U[2026-11-09 08:00:00Z], ~U[2026-11-14 08:00:00Z]]
  end

  describe "the unit of a series" do
    test "is the unit of the newest measurement, and another unit converts to it" do
      [series] =
        Series.from_entries([
          entry("a", ~U[2026-10-31 08:00:00Z], "0.61", "kg"),
          entry("b", ~U[2026-11-05 08:00:00Z], "690", "g")
        ])

      assert series.unit_label == "g"
      assert [converted, as_recorded] = series.points
      assert Decimal.equal?(converted.value, 610)
      assert converted.converted?
      # The point keeps what the member recorded.
      assert Decimal.to_string(converted.recorded) == "0.61"
      assert converted.recorded_unit == "kg"
      refute as_recorded.converted?
      assert Decimal.equal?(as_recorded.change, 80)
    end

    test "a temperature converts too" do
      [series] =
        Series.from_entries([
          entry("a", ~U[2026-11-07 08:00:00Z], "101.3", "°F",
            kind: @temperature,
            label: "Temperature"
          ),
          entry("b", ~U[2026-11-08 08:00:00Z], "38.5", "°C",
            kind: @temperature,
            label: "Temperature"
          )
        ])

      assert series.unit_label == "°C"
      assert Decimal.equal?(hd(series.points).value, Decimal.new("38.5"))
    end

    test "a measurement that does not convert is not a point" do
      [series] =
        Series.from_entries([
          entry("a", ~U[2026-11-22 08:00:00Z], "0.5", "bag"),
          entry("b", ~U[2026-11-23 08:00:00Z], "85", "g"),
          entry("c", ~U[2026-11-24 08:00:00Z], "1", nil),
          entry("d", ~U[2026-11-25 08:00:00Z], "5", "mL"),
          entry("e", ~U[2026-11-26 08:00:00Z], "110", "g")
        ])

      assert Enum.map(series.points, & &1.entry_id) == ["b", "e"]
      assert Enum.map(series.others, & &1.entry_id) == ["a", "c", "d"]
      # The change is from the point before, and not from what is not a point.
      assert changes(series.points) == [nil, "25"]
    end

    test "a series with no unit holds the measurements with no unit" do
      [series] =
        Series.from_entries([
          entry("a", ~U[2026-10-03 08:00:00Z], "3", nil),
          entry("b", ~U[2026-10-24 08:00:00Z], "4", "g"),
          entry("c", ~U[2026-11-14 08:00:00Z], "5", nil)
        ])

      assert series.unit == nil
      assert series.unit_label == nil
      assert values(series.points) == ["3", "5"]
      assert Enum.map(series.others, & &1.entry_id) == ["b"]
    end

    test "a unit that only the organisation knows is a unit of its own" do
      [series] =
        Series.from_entries([
          entry("a", ~U[2026-11-22 08:00:00Z], "1", "scoop"),
          entry("b", ~U[2026-11-23 08:00:00Z], "85", "g"),
          entry("c", ~U[2026-11-24 08:00:00Z], "2", "scoop")
        ])

      assert series.unit == nil
      assert series.unit_label == "scoop"
      assert values(series.points) == ["1", "2"]
      assert Enum.map(series.others, & &1.entry_id) == ["b"]
    end
  end

  describe "the series of a kind with a standard unit (ADR 0094)" do
    # An entry whose kind names its standard unit, as `Rescord.Journal` loads it.
    defp standard_entry(id, at, value, unit, standard) do
      entry = entry(id, at, value, unit)

      kind =
        Map.put(entry.measurement.measure_kind, :standard_unit, %{
          id: "unit-" <> standard,
          label: standard
        })

      put_in(entry.measurement.measure_kind, kind)
    end

    test "is in the standard unit, whatever the unit of the newest measurement" do
      [series] =
        Series.from_entries([
          standard_entry("a", ~U[2026-11-05 08:00:00Z], "690", "g", "g"),
          standard_entry("b", ~U[2026-11-09 08:00:00Z], "0.76", "kg", "g")
        ])

      assert {series.unit_id, series.unit_label, series.unit.code} == {"unit-g", "g", "g"}
      assert series.standard?
      assert values(series.points) == ["690", "760"]
      assert changes(series.points) == [nil, "70"]

      assert [%{converted?: false}, %{converted?: true, recorded_unit: "kg"} = newest] =
               series.points

      assert Decimal.equal?(newest.recorded, Decimal.new("0.76"))
    end

    test "is in the standard unit when no measurement has it" do
      [series] =
        Series.from_entries([standard_entry("a", ~U[2026-11-05 08:00:00Z], "1.5", "lb", "g")])

      assert series.unit_label == "g"
      assert values(series.points) == ["680.388555"]
    end

    test "leaves out a measurement that does not convert to the standard unit" do
      [series] =
        Series.from_entries([
          standard_entry("a", ~U[2026-11-05 08:00:00Z], "690", nil, "g"),
          standard_entry("b", ~U[2026-11-09 08:00:00Z], "2", "bag", "g"),
          standard_entry("c", ~U[2026-11-14 08:00:00Z], "760", "g", "g")
        ])

      assert values(series.points) == ["760"]
      assert Enum.map(series.others, & &1.entry_id) == ["a", "b"]
    end

    test "has no standard unit when the kind has none" do
      [series] = Series.from_entries([entry("a", ~U[2026-11-05 08:00:00Z], "690", "g")])

      refute series.standard?
    end
  end

  test "two measurements at one instant have an order that does not change" do
    at = ~U[2026-11-05 08:00:00Z]
    entries = [entry("b", at, "2", "g"), entry("a", at, "1", "g")]

    assert [%{points: [%{entry_id: "a"}, %{entry_id: "b"}]}] = Series.from_entries(entries)

    assert [%{points: [%{entry_id: "a"}, %{entry_id: "b"}]}] =
             Series.from_entries(Enum.reverse(entries))
  end

  test "a time range keeps the points from an instant on, each with the change that it had" do
    [series] =
      Series.from_entries([
        entry("a", ~U[2026-10-01 08:00:00Z], "600", "g"),
        entry("b", ~U[2026-11-05 08:00:00Z], "690", "g"),
        entry("c", ~U[2026-11-09 08:00:00Z], "5", "mL"),
        entry("d", ~U[2026-11-14 08:00:00Z], "760", "g")
      ])

    assert Series.since(series, nil) == series

    since = Series.since(series, ~U[2026-11-05 08:00:00Z])
    assert Enum.map(since.points, & &1.entry_id) == ["b", "d"]
    assert changes(since.points) == ["90", "70"]
    assert Enum.map(since.others, & &1.entry_id) == ["c"]

    assert %{points: [], others: []} = Series.since(series, ~U[2026-12-01 00:00:00Z])
  end

  test "the extent is the least and the greatest point, the newer of two equal ones" do
    [series] =
      Series.from_entries([
        entry("a", ~U[2026-11-05 08:00:00Z], "690", "g"),
        entry("b", ~U[2026-11-09 08:00:00Z], "672", "g"),
        entry("c", ~U[2026-11-14 08:00:00Z], "760", "g"),
        entry("d", ~U[2026-11-21 08:00:00Z], "672", "g"),
        entry("e", ~U[2026-11-28 08:00:00Z], "760", "g")
      ])

    assert {%{entry_id: "d"}, %{entry_id: "e"}} = Series.extent(series)
    assert Series.extent(%{series | points: []}) == nil
    assert Series.newest(%{series | points: []}) == nil
  end

  describe "a series in the unit of another" do
    setup do
      [grams] = Series.from_entries([entry("a", ~U[2026-11-05 08:00:00Z], "690", "g")])

      [kilograms] =
        Series.from_entries([
          entry("b", ~U[2026-11-05 08:00:00Z], "0.7", "kg"),
          entry("c", ~U[2026-11-12 08:00:00Z], "0.81", "kg")
        ])

      {:ok, grams: grams, kilograms: kilograms}
    end

    test "is itself when the unit is the same", %{grams: grams} do
      assert Series.like(grams, grams) == {:ok, grams}
    end

    test "has each value and each change in that unit", %{grams: grams, kilograms: kilograms} do
      assert {:ok, like} = Series.like(kilograms, grams)
      assert like.unit_label == "g"
      assert like.unit_id == grams.unit_id
      assert [first, second] = like.points
      assert Decimal.equal?(first.value, 700)
      assert Decimal.equal?(second.value, 810)
      assert Decimal.equal?(second.change, 110)
      assert first.converted? and second.converted?
      # What the member recorded stays.
      assert Decimal.to_string(first.recorded) == "0.7"
      assert first.recorded_unit == "kg"
    end

    test "is not there for a unit that does not convert", %{grams: grams} do
      [scoops] = Series.from_entries([entry("d", ~U[2026-11-05 08:00:00Z], "2", "scoop")])
      [none] = Series.from_entries([entry("e", ~U[2026-11-05 08:00:00Z], "2", nil)])
      [volume] = Series.from_entries([entry("f", ~U[2026-11-05 08:00:00Z], "2", "mL")])

      assert Series.like(scoops, grams) == :error
      assert Series.like(grams, scoops) == :error
      assert Series.like(none, grams) == :error
      assert Series.like(volume, grams) == :error
      # Two series with no unit are in the same unit: none.
      assert Series.like(none, none) == {:ok, none}
    end
  end
end
