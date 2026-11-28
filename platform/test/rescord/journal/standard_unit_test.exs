defmodule Rescord.Journal.StandardUnitTest do
  @moduledoc """
  Holds the rule of a measurement of a kind with a standard unit (ADR
  0094): a new measurement has the standard unit or a unit that Rescord
  converts to it, the record keeps what the person recorded, an older
  measurement stays and can be corrected, and each read gives the
  measurement in the standard unit. `Rescord.Journal.StandardTest` holds
  the conversion with no database.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Journal
  alias Rescord.Lists

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]

    {:ok,
     organisation: organisation,
     administrator: administrator,
     lists: lists,
     admin: [actor: administrator, tenant: organisation],
     options: options,
     biscuit: resident!(lists, options)}
  end

  defp measure(context, value, unit, extra \\ %{}) do
    %{
      resident_id: context.biscuit.id,
      kind: :measurement,
      measure_kind_id: context.lists.measure_kind.weight,
      value: value,
      unit_id: unit && Map.fetch!(context.lists.unit, unit)
    }
    |> Map.merge(extra)
    |> Journal.write_entry(context.options)
  end

  defp standard!(context, unit) do
    {:ok, _} =
      Lists.set_standard_unit(
        context.lists.measure_kind.weight,
        unit && Map.fetch!(context.lists.unit, unit),
        context.admin
      )
  end

  defp journal(context) do
    {:ok, entries} = Journal.entries(context.biscuit.id, context.options)
    entries
  end

  # The digits of a number, with no zero at its end: 610 g is `0.610` kg.
  defp number(%Decimal{} = value),
    do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  describe "a new measurement of a kind with a standard unit" do
    setup context do
      standard!(context, :g)
      :ok
    end

    test "has the standard unit, or a unit that Rescord converts to it", context do
      assert {:ok, _} = measure(context, "610", :g)
      assert {:ok, _} = measure(context, "0.61", :kg)
    end

    test "needs a unit", context do
      assert {:error, %Ash.Error.Invalid{} = error} = measure(context, "610", nil)

      assert Rescord.Accounts.error_messages(error) == [
               "Unit is needed: a measurement of this kind has a unit, such as g"
             ]
    end

    test "is refused in a unit that Rescord does not convert to it", context do
      assert {:error, %Ash.Error.Invalid{} = error} = measure(context, "2", :bag)

      assert Rescord.Accounts.error_messages(error) == [
               "Unit is not a unit that Rescord converts to g, the unit of this kind"
             ]

      assert journal(context) == []
    end

    test "of another kind follows the rule of that kind alone", context do
      temperature = %{measure_kind_id: context.lists.measure_kind.temperature}

      assert {:ok, _} = measure(context, "38.5", nil, temperature)
      assert {:ok, _} = measure(context, "2", :bag, temperature)
    end

    test "keeps what the person recorded, and reads in the standard unit", context do
      {:ok, _} = measure(context, "0.61", :kg)

      assert [%{measurement: measurement}] = journal(context)
      assert number(measurement.value) == "0.61"
      assert measurement.unit_id == context.lists.unit.kg

      standard = Journal.standard(measurement)
      assert {number(standard.value), standard.unit_label} == {"610", "g"}
      assert {number(standard.recorded), standard.recorded_unit} == {"0.61", "kg"}
      assert standard.converted?
    end
  end

  describe "a measurement from before the standard unit of its kind" do
    setup context do
      {:ok, no_unit} = measure(context, "610", nil)
      {:ok, bags} = measure(context, "2", :bag)
      {:ok, kilograms} = measure(context, "0.7", :kg)
      standard!(context, :g)

      {:ok, no_unit: no_unit, bags: bags, kilograms: kilograms}
    end

    test "stays as it was recorded", context do
      recorded =
        for %{measurement: measurement} <- journal(context) do
          standard = Journal.standard(measurement)
          {number(standard.value), standard.unit_label, standard.standard?}
        end

      assert Enum.sort(recorded) == [{"2", "bag", false}, {"610", nil, false}, {"700", "g", true}]
    end

    test "has its value or its words corrected with no new unit", context do
      assert {:ok, _} = Journal.correct_entry(context.no_unit, %{value: "615"}, context.options)
      assert {:ok, _} = Journal.correct_entry(context.bags, %{note: "Two bags."}, context.options)

      values = for %{measurement: measurement} <- journal(context), do: number(measurement.value)
      assert Enum.sort(values) == ["0.7", "2", "615"]
    end

    test "gets a unit that converts with a correction, and no other unit", context do
      %{lists: lists, options: options} = context

      assert {:error, %Ash.Error.Invalid{} = error} =
               Journal.correct_entry(context.kilograms, %{unit_id: lists.unit.bag}, options)

      assert Rescord.Accounts.error_messages(error) == [
               "Unit is not a unit that Rescord converts to g, the unit of this kind"
             ]

      assert {:ok, _} = Journal.correct_entry(context.no_unit, %{unit_id: lists.unit.g}, options)
    end

    test "is not in the series, which is in the standard unit", context do
      {:ok, [weight]} = Journal.series(context.biscuit.id, context.options)

      assert weight.standard?
      assert {weight.unit_id, weight.unit_label} == {context.lists.unit.g, "g"}
      assert Enum.map(weight.points, &number(&1.value)) == ["700"]

      assert Enum.sort(Enum.map(weight.others, & &1.entry_id)) ==
               Enum.sort([context.no_unit.id, context.bags.id])
    end
  end

  test "a new standard unit of the kind changes what each read shows, and no record", context do
    {:ok, _} = measure(context, "610", :g)
    standard!(context, :kg)

    assert [%{measurement: measurement}] = journal(context)
    assert {number(measurement.value), measurement.unit_id} == {"610", context.lists.unit.g}
    assert {"0.61", "kg"} == standard(measurement)

    {:ok, [weight]} = Journal.series(context.biscuit.id, context.options)
    assert {weight.unit_label, Enum.map(weight.points, &number(&1.value))} == {"kg", ["0.61"]}

    # With no standard unit again, each read shows what was recorded.
    standard!(context, nil)
    assert [%{measurement: measurement}] = journal(context)
    assert {"610", "g"} == standard(measurement)
  end

  defp standard(measurement) do
    standard = Journal.standard(measurement)
    {number(standard.value), standard.unit_label}
  end

  test "the export has the measurement as recorded, and in the standard unit", context do
    standard!(context, :g)
    {:ok, _} = measure(context, "0.61", :kg)

    {:ok, _} =
      measure(context, "38.5", nil, %{measure_kind_id: context.lists.measure_kind.temperature})

    today = Rescord.Accounts.today(context.organisation)

    assert {:ok, export} =
             Rescord.Export.export(context.organisation, today, actor: context.administrator)

    {:ok, entries} = :zip.unzip(export.zip, [:memory])

    file = fn wanted ->
      [csv] = for {name, bytes} <- entries, Path.basename(to_string(name)) == wanted, do: bytes
      csv
    end

    # The kind has its standard unit in the export too.
    assert file.("measure_kinds.csv") =~ "standard_unit_id"
    assert file.("measure_kinds.csv") =~ context.lists.unit.g

    csv = file.("measurements.csv")

    [header | rows] = csv |> String.trim_leading("﻿") |> String.split("\r\n", trim: true)
    columns = String.split(header, ",")

    assert Enum.take(columns, -2) == ["standard_value", "standard_unit"]

    rows =
      for row <- rows do
        row = columns |> Enum.zip(String.split(row, ",")) |> Map.new()
        Map.take(row, ["value", "unit_id", "standard_value", "standard_unit"])
      end

    assert Enum.sort_by(rows, & &1["value"]) == [
             %{
               "value" => "0.61",
               "unit_id" => context.lists.unit.kg,
               "standard_value" => "610",
               "standard_unit" => "g"
             },
             %{"value" => "38.5", "unit_id" => "", "standard_value" => "", "standard_unit" => ""}
           ]
  end
end
