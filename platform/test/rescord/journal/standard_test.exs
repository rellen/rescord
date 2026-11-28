defmodule Rescord.Journal.StandardTest do
  @moduledoc """
  Holds a measurement in the standard unit of its kind (ADR 0094): what
  converts, what stays as it was recorded, and that the recorded value is
  kept. The measurements here are plain maps, with the fields that
  `Rescord.Journal` loads: the module reads no database.
  """

  use ExUnit.Case, async: true

  alias Rescord.Journal.Standard

  defp unit(nil), do: nil
  defp unit(label), do: %{id: "unit-" <> label, label: label}

  defp measurement(value, unit, standard) do
    %{
      value: Decimal.new(value),
      unit_id: unit && "unit-" <> unit,
      unit: unit(unit),
      measure_kind: %{label: "Weight", standard_unit: unit(standard)}
    }
  end

  defp number(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  test "a measurement of a kind with no standard unit is as it was recorded" do
    standard = Standard.of(measurement("0.61", "kg", nil))

    assert {number(standard.value), standard.unit_label} == {"0.61", "kg"}
    assert standard.unit.code == "kg"
    refute standard.standard?
    refute standard.converted?
  end

  test "a measurement in the standard unit is not converted" do
    standard = Standard.of(measurement("610", "g", "g"))

    assert {number(standard.value), standard.unit_label} == {"610", "g"}
    assert standard.standard?
    refute standard.converted?
  end

  test "a measurement in another unit of the same sort is converted, and keeps what was recorded" do
    standard = Standard.of(measurement("0.61", "kg", "g"))

    assert {number(standard.value), standard.unit_label} == {"610", "g"}
    assert standard.unit.code == "g"
    assert {number(standard.recorded), standard.recorded_unit} == {"0.61", "kg"}
    assert standard.standard?
    assert standard.converted?
  end

  test "no number is rounded" do
    standard = Standard.of(measurement("2", "lb", "kg"))

    assert number(standard.value) == "0.90718474"
  end

  test "a temperature converts with its zero point" do
    standard = Standard.of(measurement("101.3", "°F", "°C"))

    assert number(Decimal.round(standard.value, 2)) == "38.50"
    assert standard.converted?
  end

  test "a measurement that does not convert is as it was recorded" do
    for {unit, standard_unit} <- [{nil, "g"}, {"bag", "g"}, {"cm", "g"}, {"g", "bag"}] do
      standard = Standard.of(measurement("3", unit, standard_unit))

      assert {number(standard.value), standard.unit_label} == {"3", unit}
      refute standard.standard?
      refute standard.converted?
    end
  end

  test "a unit that only the organisation knows is a standard unit too" do
    standard = Standard.of(measurement("2", "bag", "bag"))

    assert {number(standard.value), standard.unit_label, standard.unit} == {"2", "bag", nil}
    assert standard.standard?
  end

  test "a measurement whose kind is not loaded is as it was recorded" do
    measurement = %{
      value: Decimal.new("5"),
      unit_id: "unit-g",
      unit: unit("g"),
      measure_kind: %Ash.NotLoaded{}
    }

    refute Standard.of(measurement).standard?
    assert Standard.standard_unit(measurement) == nil
  end
end
