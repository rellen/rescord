defmodule RescordWeb.MeasurementWordsTest do
  @moduledoc """
  Holds the words of the measurements over time (ADR 0080): a value in the
  unit of its series, a change, and the words that say what a chart shows.
  """

  use ExUnit.Case, async: true

  alias Rescord.Journal.Series
  alias RescordWeb.MeasurementWords

  doctest MeasurementWords

  defp entry(id, at, value, unit) do
    %{
      id: id,
      happened_at: at,
      note: nil,
      measurement: %{
        value: Decimal.new(value),
        measure_kind_id: "kind",
        measure_kind: %{label: "Weight"},
        unit_id: unit && "unit-" <> unit,
        unit: unit && %{label: unit}
      }
    }
  end

  defp series(rows) do
    [series] =
      Series.from_entries(for {id, at, value, unit} <- rows, do: entry(id, at, value, unit))

    series
  end

  defp date(%DateTime{} = at), do: Calendar.strftime(at, "%-d %B")

  test "a value has the unit of its series" do
    grams = series([{"a", ~U[2026-11-05 08:00:00Z], "1095", "g"}])
    scoops = series([{"a", ~U[2026-11-05 08:00:00Z], "1095", "scoop"}])
    none = series([{"a", ~U[2026-11-05 08:00:00Z], "1095", nil}])

    assert MeasurementWords.value(grams, Decimal.new("1095")) == "1,095 g"
    assert MeasurementWords.value(scoops, Decimal.new("1095.50")) == "1,095.5 scoop"
    assert MeasurementWords.value(none, Decimal.new("1095")) == "1,095"
  end

  test "a value in the unit of the series keeps each digit, and a converted one is rounded" do
    series =
      series([
        {"a", ~U[2026-11-01 08:00:00Z], "2", "lb"},
        {"b", ~U[2026-11-05 08:00:00Z], "0.90718474", "kg"}
      ])

    assert [converted, as_recorded] = series.points
    assert MeasurementWords.shown(series, converted) == "0.9072 kg"
    assert MeasurementWords.recorded(converted) == "2 lb"
    assert MeasurementWords.shown(series, as_recorded) == "0.90718474 kg"
    assert MeasurementWords.recorded(as_recorded) == "0.90718474 kg"
  end

  test "what was recorded with no unit is the number" do
    series = series([{"a", ~U[2026-11-01 08:00:00Z], "4", nil}])
    assert MeasurementWords.recorded(hd(series.points)) == "4"
  end

  test "a change has a direction and an amount with no sign" do
    series =
      series([
        {"a", ~U[2026-11-05 08:00:00Z], "690", "g"},
        {"b", ~U[2026-11-09 08:00:00Z], "672", "g"},
        {"c", ~U[2026-11-14 08:00:00Z], "760", "g"},
        {"d", ~U[2026-11-21 08:00:00Z], "760", "g"}
      ])

    assert Enum.map(series.points, &MeasurementWords.change(series, &1)) ==
             [nil, {:down, "18 g"}, {:up, "88 g"}, {:same, "0 g"}]

    assert Enum.map(
             series.points,
             &MeasurementWords.change_words(series, &1, fn at -> date(at) end)
           ) ==
             [
               nil,
               "18 g less than on 5 November",
               "88 g more than on 9 November",
               "The same as on 14 November"
             ]
  end

  test "the change of a temperature is a difference, and not a temperature" do
    series =
      series([
        {"a", ~U[2026-11-07 08:00:00Z], "38.6", "°C"},
        {"b", ~U[2026-11-08 08:00:00Z], "39.4", "°C"}
      ])

    assert MeasurementWords.change(series, List.last(series.points)) == {:up, "0.8 °C"}
  end

  describe "the words that say what a chart shows" do
    test "say how many, from when to when, the lowest, the highest and the newest" do
      series =
        series([
          {"a", ~U[2026-11-05 08:00:00Z], "690", "g"},
          {"b", ~U[2026-11-09 08:00:00Z], "672", "g"},
          {"c", ~U[2026-11-14 08:00:00Z], "870", "g"},
          {"d", ~U[2026-11-21 08:00:00Z], "760", "g"}
        ])

      assert MeasurementWords.summary(series, &date/1) ==
               "4 measurements from 5 November to 21 November. " <>
                 "The lowest is 672 g, on 9 November. " <>
                 "The highest is 870 g, on 14 November. " <>
                 "The newest is 760 g."
    end

    test "are short for one measurement and for none" do
      series = series([{"a", ~U[2026-11-05 08:00:00Z], "690", "g"}])

      assert MeasurementWords.summary(series, &date/1) == "One measurement: 690 g on 5 November."
      assert MeasurementWords.summary(%{series | points: []}, &date/1) == "No measurement."
    end
  end

  test "four digits keep each digit before the point, and small numbers" do
    four = &(&1 |> Decimal.new() |> MeasurementWords.four_digits() |> Decimal.to_string(:normal))

    assert four.("0.90718474") == "0.9072"
    assert four.("907.18474") == "907.2"
    assert four.("12345.67") == "12346"
    assert four.("0.000251234") == "0.0002512"
    assert four.("-18.25678") == "-18.26"
    assert four.("0") == "0"
    assert four.("610") == "610"
  end
end
