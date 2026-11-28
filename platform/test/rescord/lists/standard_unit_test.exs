defmodule Rescord.Lists.StandardUnitTest do
  @moduledoc """
  Holds the standard unit of a measure kind (ADR 0094): who sets it, which
  unit it can be, the units that a measurement of the kind can then have,
  and what the migration fills for a kind that was there before.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Journal
  alias Rescord.Lists

  @migration Rescord.Repo.TenantMigrations.AddTheStandardUnitOfAMeasureKind

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)

    {:ok,
     root: root,
     organisation: organisation,
     lists: lists,
     admin: [actor: administrator, tenant: organisation],
     options: [actor: member, tenant: organisation]}
  end

  defp kind!(id, options), do: Ash.get!(Lists.MeasureKind, id, options)

  describe "the standard unit of a measure kind" do
    test "is empty at first, and an administrator sets it and removes it", context do
      %{lists: lists, admin: admin} = context
      assert kind!(lists.measure_kind.weight, admin).standard_unit_id == nil

      assert {:ok, weight} =
               Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.g, admin)

      assert weight.standard_unit_id == lists.unit.g
      assert kind!(lists.measure_kind.weight, admin).standard_unit_id == lists.unit.g

      # The other kind stays as it was.
      assert kind!(lists.measure_kind.temperature, admin).standard_unit_id == nil

      assert {:ok, weight} = Lists.set_standard_unit(lists.measure_kind.weight, nil, admin)
      assert weight.standard_unit_id == nil
    end

    test "is not for a member to set", context do
      %{lists: lists} = context

      assert {:error, %Ash.Error.Forbidden{}} =
               Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.g, context.options)

      assert kind!(lists.measure_kind.weight, context.admin).standard_unit_id == nil
    end

    test "is a unit of the organisation", context do
      %{lists: lists, admin: admin} = context

      # The id of a value of another list, and an id of nothing.
      for id <- [lists.species.rabbit, Ash.UUID.generate()] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Lists.set_standard_unit(lists.measure_kind.weight, id, admin)

        assert Rescord.Accounts.error_messages(error) == [
                 "Standard unit is not a unit of the organisation"
               ]
      end
    end

    test "is one of the units of the kind, when the kind names units", context do
      %{lists: lists, admin: admin} = context
      {:ok, _} = Lists.set_units(lists.measure_kind.weight, [lists.unit.g, lists.unit.kg], admin)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.bag, admin)

      assert Rescord.Accounts.error_messages(error) == [
               "Standard unit is not one of the units of this kind of measurement"
             ]

      assert {:ok, %{standard_unit_id: kg}} =
               Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.kg, admin)

      assert kg == lists.unit.kg
    end

    test "stays one of the units of the kind when the units change", context do
      %{lists: lists, admin: admin} = context
      {:ok, _} = Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.g, admin)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Lists.set_units(lists.measure_kind.weight, [lists.unit.kg, lists.unit.bag], admin)

      assert Rescord.Accounts.error_messages(error) == [
               "Unit ids must keep the standard unit of the kind. Change the standard unit first"
             ]

      # With the standard unit among them, and with no unit at all.
      assert {:ok, weight} =
               Lists.set_units(lists.measure_kind.weight, [lists.unit.g, lists.unit.kg], admin)

      assert weight.standard_unit_id == lists.unit.g
      assert {:ok, %{unit_ids: []}} = Lists.set_units(lists.measure_kind.weight, [], admin)
    end

    test "is the one unit of a kind that gets exactly one unit", context do
      %{lists: lists, admin: admin} = context

      assert {:ok, weight} = Lists.set_units(lists.measure_kind.weight, [lists.unit.g], admin)
      assert weight.standard_unit_id == lists.unit.g

      # Two units are a choice, which Rescord does not make.
      assert {:ok, temperature} =
               Lists.set_units(
                 lists.measure_kind.temperature,
                 [lists.unit.g, lists.unit.kg],
                 admin
               )

      assert temperature.standard_unit_id == nil
    end
  end

  describe "the units that a measurement of a kind can have" do
    @g %{id: "g", label: "g"}
    @kg %{id: "kg", label: "kg"}
    @lb %{id: "lb", label: "lb"}
    @cm %{id: "cm", label: "cm"}
    @bag %{id: "bag", label: "bag"}
    @units [@bag, @cm, @g, @kg, @lb]

    test "are the standard unit first, and the units that convert to it" do
      kind = %{unit_ids: [], standard_unit_id: "g"}
      assert Lists.accepted_units(kind, @units) == [@g, @kg, @lb]

      # Only the units that the kind names, when it names units.
      kind = %{unit_ids: ["g", "kg", "bag"], standard_unit_id: "g"}
      assert Lists.accepted_units(kind, @units) == [@g, @kg]
    end

    test "are the standard unit alone, when Rescord does not know it" do
      kind = %{unit_ids: [], standard_unit_id: "bag"}
      assert Lists.accepted_units(kind, @units) == [@bag]
    end

    test "are the units of the kind, or each unit, with no standard unit" do
      assert Lists.accepted_units(%{unit_ids: [], standard_unit_id: nil}, @units) == @units

      assert Lists.accepted_units(%{unit_ids: ["kg", "g"], standard_unit_id: nil}, @units) == [
               @g,
               @kg
             ]

      # A standard unit that is not in the list of units decides nothing.
      assert Lists.accepted_units(%{unit_ids: [], standard_unit_id: "gone"}, @units) == @units
    end

    test "are what the rule of the journal reads", context do
      %{lists: lists, admin: admin} = context
      weight = lists.measure_kind.weight

      assert Lists.units_for(weight, admin) == :any
      assert Lists.units_for(Ash.UUID.generate(), admin) == :any

      {:ok, _} = Lists.set_units(weight, [lists.unit.g, lists.unit.kg, lists.unit.bag], admin)
      assert {:of_kind, ids} = Lists.units_for(weight, admin)
      assert Enum.sort(ids) == Enum.sort([lists.unit.g, lists.unit.kg, lists.unit.bag])

      {:ok, _} = Lists.set_standard_unit(weight, lists.unit.g, admin)
      assert {:standard, "g", [first | _] = ids} = Lists.units_for(weight, admin)
      assert first == lists.unit.g
      assert Enum.sort(ids) == Enum.sort([lists.unit.g, lists.unit.kg])

      # With no unit named, each unit that converts.
      {:ok, _} = Lists.set_units(weight, [], admin)
      assert {:standard, "g", ids} = Lists.units_for(weight, admin)
      assert Enum.sort(ids) == Enum.sort([lists.unit.g, lists.unit.kg])
    end
  end

  describe "the migration that adds the standard unit" do
    setup context do
      Code.ensure_loaded?(@migration) ||
        Code.require_file(
          "priv/repo/tenant_migrations/20261128080500_add_the_standard_unit_of_a_measure_kind.exs"
        )

      %{lists: lists, admin: admin, options: options} = context

      added =
        for {key, name} <- [unit: "cm", measure_kind: "Length", measure_kind: "Girth"],
            into: %{} do
          {:ok, value} = Lists.add_local_value(key, name, admin)
          {name, value.id}
        end

      biscuit = resident!(lists, options)

      measure = fn kind, value, unit ->
        Journal.write_entry!(
          %{
            resident_id: biscuit.id,
            kind: :measurement,
            measure_kind_id: kind,
            value: value,
            unit_id: unit
          },
          options
        )
      end

      {:ok,
       prefix: Rescord.Accounts.Organisation.schema(context.organisation),
       added: added,
       measure: measure}
    end

    # As the schema was before the migration filled the column.
    defp empty!(prefix) do
      Rescord.Repo.query!(~s(UPDATE "#{prefix}"."measure_kinds" SET standard_unit_id = NULL))
    end

    defp fill!(prefix) do
      # The module of a migration is not compiled with the application.
      for statement <- apply(@migration, :fill, [prefix]), do: Rescord.Repo.query!(statement)
    end

    test "gives a kind with exactly one unit that unit, in each version of the kind", context do
      %{lists: lists, admin: admin, prefix: prefix} = context
      {:ok, _} = Lists.set_units(lists.measure_kind.weight, [lists.unit.g], admin)
      empty!(prefix)
      assert kind!(lists.measure_kind.weight, admin).standard_unit_id == nil

      fill!(prefix)

      assert kind!(lists.measure_kind.weight, admin).standard_unit_id == lists.unit.g
      assert kind!(lists.measure_kind.temperature, admin).standard_unit_id == nil

      # The kind has a version from before its units, and one since.
      assert %{rows: [[2, 2]]} =
               Rescord.Repo.query!(
                 ~s|SELECT count(*), count(standard_unit_id) FROM "#{prefix}"."measure_kinds" WHERE id = $1|,
                 [Ecto.UUID.dump!(lists.measure_kind.weight)]
               )
    end

    test "gives a kind the one unit that each of its measurements has", context do
      %{lists: lists, admin: admin, prefix: prefix, added: added, measure: measure} = context
      cm = added["cm"]

      # Length: each measurement is in cm now. One was in g, and is corrected.
      measure.(added["Length"], "24", cm)
      wrong = measure.(added["Length"], "25", lists.unit.g)
      {:ok, _} = Journal.correct_entry(wrong, %{unit_id: cm}, context.options)

      # Weight names two units, and each measurement has one of them.
      {:ok, _} = Lists.set_units(lists.measure_kind.weight, [lists.unit.g, lists.unit.kg], admin)
      measure.(lists.measure_kind.weight, "870", lists.unit.g)
      measure.(lists.measure_kind.weight, "905", lists.unit.g)

      empty!(prefix)
      fill!(prefix)

      assert kind!(added["Length"], admin).standard_unit_id == cm
      assert kind!(lists.measure_kind.weight, admin).standard_unit_id == lists.unit.g
    end

    test "leaves a kind with no standard unit when the answer is a guess", context do
      %{lists: lists, admin: admin, prefix: prefix, added: added, measure: measure} = context

      # Two units among the measurements.
      measure.(added["Girth"], "20", added["cm"])
      measure.(added["Girth"], "0.2", lists.unit.g)

      # A measurement with no unit.
      measure.(lists.measure_kind.temperature, "38.5", nil)
      measure.(lists.measure_kind.temperature, "38.9", added["cm"])

      # Two units named, and no measurement: Weight. No unit and no
      # measurement: Length.
      {:ok, _} = Lists.set_units(lists.measure_kind.weight, [lists.unit.g, lists.unit.kg], admin)

      empty!(prefix)
      fill!(prefix)

      for id <- [
            added["Girth"],
            added["Length"],
            lists.measure_kind.temperature,
            lists.measure_kind.weight
          ] do
        assert kind!(id, admin).standard_unit_id == nil
      end
    end

    test "keeps a standard unit that is there, and a second run changes nothing", context do
      %{lists: lists, admin: admin, prefix: prefix, measure: measure} = context

      measure.(lists.measure_kind.weight, "870", lists.unit.g)
      measure.(lists.measure_kind.temperature, "0.9", lists.unit.kg)
      empty!(prefix)

      # An administrator chose kg for the weight before the run.
      {:ok, _} = Lists.set_standard_unit(lists.measure_kind.weight, lists.unit.kg, admin)

      fill!(prefix)
      assert kind!(lists.measure_kind.weight, admin).standard_unit_id == lists.unit.kg
      assert kind!(lists.measure_kind.temperature, admin).standard_unit_id == lists.unit.kg

      assert [%{num_rows: 0}, %{num_rows: 0}] = fill!(prefix)
    end

    test "changes no measurement", context do
      %{lists: lists, prefix: prefix, measure: measure} = context
      measure.(lists.measure_kind.weight, "0.87", lists.unit.kg)

      read = fn ->
        Rescord.Repo.query!(
          ~s(SELECT id, value, unit_id, valid_at FROM "#{prefix}"."measurements" ORDER BY id)
        ).rows
      end

      before = read.()
      empty!(prefix)
      fill!(prefix)

      assert read.() == before
    end
  end
end
