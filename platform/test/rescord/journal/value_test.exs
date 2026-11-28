defmodule Rescord.Journal.ValueTest do
  @moduledoc """
  Holds the rules of the value of a measurement (ADR 0117): a mass, a
  length or a volume is more than 0, and a kind with a range refuses a
  value outside it, in any unit that converts to its standard unit. The
  range of a kind is in its standard unit, follows a new standard unit,
  and is for an administrator to set.

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
    {:ok, kind} =
      Lists.set_standard_unit(
        context.lists.measure_kind.weight,
        unit && Map.fetch!(context.lists.unit, unit),
        context.admin
      )

    kind
  end

  defp range!(context, lowest, highest) do
    {:ok, kind} =
      Lists.set_range(context.lists.measure_kind.weight, lowest, highest, context.admin)

    kind
  end

  defp messages({:error, error}), do: Rescord.Accounts.error_messages(error)

  defp number(nil), do: nil
  defp number(%Decimal{} = value), do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  describe "a measurement in a unit of mass" do
    test "is more than 0", context do
      assert messages(measure(context, "0", :g)) == ["Value must be more than 0"]
      assert messages(measure(context, "-5", :kg)) == ["Value must be more than 0"]
      assert {:ok, _} = measure(context, "0.001", :kg)
    end

    test "is more than 0 after a correction of its value", context do
      {:ok, entry} = measure(context, "610", :g)

      assert messages(Journal.correct_entry(entry, %{value: "0"}, context.options)) ==
               ["Value must be more than 0"]
    end
  end

  describe "a measurement in a unit that is not a mass, a length or a volume" do
    test "can be 0 or below", context do
      temperature = %{measure_kind_id: context.lists.measure_kind.temperature}

      # A unit that Rescord does not know, and no unit.
      assert {:ok, _} = measure(context, "0", :bag)
      assert {:ok, _} = measure(context, "-2", nil, temperature)
    end
  end

  describe "a kind with a range" do
    setup context do
      standard!(context, :g)
      range!(context, "50", "80000")
      :ok
    end

    test "takes a value inside the range, in each unit that converts", context do
      assert {:ok, _} = measure(context, "50", :g)
      assert {:ok, _} = measure(context, "80", :kg)
      assert {:ok, _} = measure(context, "1.095", :kg)
    end

    test "refuses a value outside it, as the person typed it", context do
      refused = ["Value is outside the range of Weight: 50 g to 80000 g"]

      assert messages(measure(context, "49", :g)) == refused
      # A mistake of the unit: 1095 g typed as kg.
      assert messages(measure(context, "1095", :kg)) == refused
      assert {:ok, []} = Journal.entries(context.biscuit.id, context.options)
    end

    test "checks a correction that gives the value, the unit or the kind", context do
      {:ok, entry} = measure(context, "1095", :g)

      assert messages(
               Journal.correct_entry(entry, %{unit_id: context.lists.unit.kg}, context.options)
             ) ==
               ["Value is outside the range of Weight: 50 g to 80000 g"]

      assert {:ok, _} = Journal.correct_entry(entry, %{value: "1100"}, context.options)
    end

    test "keeps an older measurement, and its correction of the words", context do
      {:ok, entry} = measure(context, "1095", :g)
      range!(context, "2000", nil)

      assert {:ok, _} = Journal.correct_entry(entry, %{note: "Before dinner."}, context.options)

      assert messages(Journal.correct_entry(entry, %{value: "1096"}, context.options)) ==
               ["Value is outside the range of Weight: at least 2000 g"]
    end
  end

  describe "the range of a measure kind" do
    test "needs a standard unit", context do
      assert messages(Lists.set_range(context.lists.measure_kind.weight, "1", "2", context.admin)) ==
               ["Lowest needs a standard unit of the kind first: the range is in that unit"]
    end

    test "has its lowest not above its highest", context do
      standard!(context, :g)

      assert messages(Lists.set_range(context.lists.measure_kind.weight, "5", "4", context.admin)) ==
               ["Highest must not be below the lowest"]

      kind = range!(context, nil, "4")
      assert {kind.lowest, number(kind.highest)} == {nil, "4"}
    end

    test "is not for a member to set", context do
      standard!(context, :g)

      assert {:error, %Ash.Error.Forbidden{}} =
               Lists.set_range(context.lists.measure_kind.weight, "1", "2", context.options)
    end

    test "converts to a new standard unit, and goes with no standard unit", context do
      standard!(context, :g)
      range!(context, "50", "80000")

      kind = standard!(context, :kg)
      assert {number(kind.lowest), number(kind.highest)} == {"0.05", "80"}

      kind = standard!(context, nil)
      assert {kind.lowest, kind.highest} == {nil, nil}
    end

    test "goes with a new standard unit of another dimension", context do
      standard!(context, :g)
      range!(context, "50", "80000")

      kind = standard!(context, :bag)
      assert {kind.lowest, kind.highest} == {nil, nil}
    end
  end
end
