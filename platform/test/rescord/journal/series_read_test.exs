defmodule Rescord.Journal.SeriesReadTest do
  @moduledoc """
  Holds the read of the measurements of a resident as series
  (`Rescord.Journal.series/2` and `series_of/2`, ADR 0080): the entries of
  the journal with the kind and the unit of each, and only for a person who
  can read the journal. `Rescord.Journal.SeriesTest` holds the series with
  no database.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Journal
  alias Rescord.Journal.Series

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]

    {:ok,
     root: root,
     organisation: organisation,
     lists: lists,
     options: options,
     biscuit: resident!(lists, options),
     crumpet: resident!(lists, options, %{name: "Crumpet"})}
  end

  defp measure!(context, resident, kind, value, unit, hours_ago) do
    Journal.write_entry!(
      %{
        resident_id: resident.id,
        kind: :measurement,
        measure_kind_id: Map.fetch!(context.lists.measure_kind, kind),
        value: value,
        unit_id: unit && Map.fetch!(context.lists.unit, unit),
        happened_at: DateTime.add(DateTime.utc_now(), -hours_ago, :hour)
      },
      context.options
    )
  end

  defp values(%Series{points: points}), do: Enum.map(points, &Decimal.to_string(&1.value))

  test "a resident has one series for each kind, with the points in the order of time",
       context do
    # Written in another order than the order of time.
    measure!(context, context.biscuit, :weight, "915", :g, 1)
    first = measure!(context, context.biscuit, :weight, "0.69", :kg, 72)
    measure!(context, context.biscuit, :weight, "760", :g, 48)
    measure!(context, context.biscuit, :temperature, "38.5", nil, 2)

    Journal.write_entry!(
      %{resident_id: context.biscuit.id, kind: :general, note: "Ate well."},
      context.options
    )

    {:ok, [temperature, weight]} = Journal.series(context.biscuit.id, context.options)

    assert {temperature.label, temperature.unit_label, values(temperature)} ==
             {"Temperature", nil, ["38.5"]}

    assert weight.label == "Weight"
    assert weight.kind_id == context.lists.measure_kind.weight
    assert weight.unit_id == context.lists.unit.g
    assert weight.unit_label == "g"

    # The measurement in kg is a point in grams, and keeps what the member recorded.
    assert [%Series.Point{entry_id: id, converted?: true, recorded_unit: "kg"} = point, _, newest] =
             weight.points

    assert id == first.id
    assert Decimal.equal?(point.value, 690)
    assert Decimal.equal?(point.recorded, Decimal.new("0.69"))
    assert Decimal.equal?(newest.change, 155)
    assert weight.others == []
  end

  test "a resident with no measurement has no series", context do
    assert {:ok, []} = Journal.series(context.biscuit.id, context.options)
    assert {:ok, %{}} = Journal.series_of([], context.options)
  end

  test "the series of some residents are by resident, in one read", context do
    measure!(context, context.biscuit, :weight, "915", :g, 1)
    measure!(context, context.crumpet, :weight, "1095", :g, 1)
    measure!(context, context.crumpet, :temperature, "38.5", nil, 2)
    other = resident!(context.lists, context.options, %{name: "Scone"})
    measure!(context, other, :weight, "930", :g, 1)

    {:ok, series} =
      Journal.series_of([context.biscuit.id, context.crumpet.id], context.options)

    assert series |> Map.keys() |> Enum.sort() ==
             Enum.sort([context.biscuit.id, context.crumpet.id])

    assert [%Series{label: "Weight"} = weight] = series[context.biscuit.id]
    assert values(weight) == ["915"]
    assert Enum.map(series[context.crumpet.id], & &1.label) == ["Temperature", "Weight"]
  end

  test "there is no series for a user of another organisation, or for nobody", context do
    measure!(context, context.biscuit, :weight, "915", :g, 1)
    outside = organisation!(context.root, "Other")
    {_, outsider} = member!(outside, :administrator, context.root)

    for actor <- [outsider, nil] do
      options = [actor: actor, tenant: context.organisation]

      assert {:ok, []} = Journal.series(context.biscuit.id, options)
      assert {:ok, series} = Journal.series_of([context.biscuit.id], options)
      assert series == %{}
    end
  end
end
