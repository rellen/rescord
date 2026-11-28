defmodule Rescord.LocationsTest do
  @moduledoc """
  Holds the locations of an organisation and who lives where
  (`docs/domain.md`, section 5.5, and ADR 0029): a location inside a
  location, a placement of a resident or a group, where a resident lives,
  the capacity, and a move at the instant that it happened.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Locations, Residents}
  alias Rescord.Accounts.Errors.InvalidTime

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    options = [actor: member, tenant: organisation]

    add = fn name, attributes ->
      Locations.add_location!(Map.put(attributes, :name, name), admin)
    end

    shed = add.("Main shed", %{})
    room = add.("Long room", %{parent_id: shed.id})
    east = add.("East 1", %{parent_id: room.id, capacity: 2})
    west = add.("West 1", %{parent_id: room.id, capacity: 2})

    pig = fn name -> resident!(lists, options, %{name: name, sex: :female}) end

    {:ok,
     root: root,
     organisation: organisation,
     admin: admin,
     options: options,
     shed: shed,
     room: room,
     east: east,
     west: west,
     fern: pig.("Fern"),
     sage: pig.("Sage"),
     basil: pig.("Basil")}
  end

  defp node(id, options) do
    {:ok, tree} = Locations.tree(options)
    Locations.find(tree, id)
  end

  defp names(placements), do: Enum.map(placements, & &1.resident.name)

  describe "the housing" do
    test "is a tree: a location is inside one other location, or inside none", context do
      {:ok, [shed]} = Locations.tree(context.options)

      assert shed.location.name == "Main shed"
      assert [%{location: %{name: "Long room"}, children: houses}] = shed.children
      assert Enum.map(houses, & &1.location.name) == ["East 1", "West 1"]

      assert Enum.map(Locations.flat([shed]), fn {node, depth} -> {node.location.name, depth} end) ==
               [{"Main shed", 0}, {"Long room", 1}, {"East 1", 2}, {"West 1", 2}]
    end

    test "does not put a location inside itself, or inside a location that it contains",
         context do
      for parent <- [context.shed, context.room, context.east] do
        assert {:error, error} = Locations.move_location(context.shed, parent.id, context.admin)

        assert Exception.message(error) =~
                 ~r/cannot be the location itself|is inside this location/
      end

      # The housing is as it was.
      assert {:ok, [%{location: %{name: "Main shed"}}]} = Locations.tree(context.options)
    end

    test "moves a location to another one, and keeps where it was at a past instant", context do
      before = DateTime.utc_now()

      assert {:ok, _tie} = Locations.move_location(context.east, context.shed.id, context.admin)

      {:ok, [shed]} = Locations.tree(context.options)
      assert Enum.map(shed.children, & &1.location.name) == ["East 1", "Long room"]

      {:ok, [then]} = Locations.tree([as_of: before] ++ context.options)
      assert Enum.map(then.children, & &1.location.name) == ["Long room"]

      # Inside none.
      assert {:ok, nil} = Locations.move_location(context.east, nil, context.admin)
      {:ok, tree} = Locations.tree(context.options)
      assert Enum.map(tree, & &1.location.name) == ["East 1", "Main shed"]
    end

    test "is shaped by an administrator, and not by a member", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Locations.add_location(%{name: "Nursery"}, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Locations.revise_location(context.east, %{capacity: 4}, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Locations.close_location(context.east, context.options)

      assert {:ok, %{capacity: 4}} =
               Locations.revise_location(context.east, %{capacity: 4}, context.admin)

      refute Locations.role_can?(:member, :location, :add)
      assert Locations.role_can?(:administrator, :location, :add)
      assert Locations.role_can?(:member, :placement, :place)
    end

    test "loses a location that an administrator closes", context do
      assert :ok = Locations.close_location(context.west, context.admin)

      assert node(context.west.id, context.options) == nil
      assert length(node(context.room.id, context.options).children) == 1
    end

    test "is not closed while it holds a resident, a group or another location", context do
      {:ok, _} = Locations.settle({:resident, context.fern.id}, context.east.id, context.options)

      for location <- [context.east, context.room] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Locations.close_location(location, context.admin)

        assert Exception.message(error) =~ "Move them first"
      end

      group = Residents.form_group!(%{resident_ids: [context.sage.id]}, context.options)
      {:ok, _} = Locations.settle({:group, group.id}, context.west.id, context.options)

      assert {:error, %Ash.Error.Invalid{}} =
               Locations.close_location(context.west, context.admin)

      # A member gets the answer of the policy, and not of the rule.
      assert {:error, %Ash.Error.Forbidden{}} =
               Locations.close_location(context.east, context.options)

      # A resident that an administrator removed is in no location.
      assert :ok = Residents.remove_resident(context.fern, context.admin)
      assert node(context.east.id, context.options).residents == []
      assert :ok = Locations.close_location(context.east, context.admin)
    end

    test "is not for a user of another organisation, or for nobody", context do
      other = organisation!(context.root, "Other")
      {_, outsider} = member!(other, :administrator, context.root)

      for actor <- [outsider, nil] do
        options = [actor: actor, tenant: context.organisation]

        assert {:ok, []} = Locations.tree(options)
        assert {:error, %Ash.Error.Forbidden{}} = Locations.add_location(%{name: "X"}, options)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Locations.settle({:resident, context.fern.id}, context.east.id, options)
      end
    end
  end

  describe "a placement" do
    test "puts a resident in a location, and a move keeps where it was", context do
      options = context.options
      resident = {:resident, context.fern.id}

      assert {:ok, _} = Locations.settle(resident, context.east.id, options)
      assert names(node(context.east.id, options).residents) == ["Fern"]
      before = DateTime.utc_now()

      assert {:ok, _} = Locations.settle(resident, context.west.id, options)
      assert node(context.east.id, options).residents == []
      assert names(node(context.west.id, options).residents) == ["Fern"]

      assert names(node(context.east.id, [as_of: before] ++ options).residents) == ["Fern"]

      # The same location again changes nothing.
      assert {:ok, _} = Locations.settle(resident, context.west.id, options)

      {:ok, [%{location: location, with: :own, placement: placement}]} =
        Locations.home(context.fern.id, options)

      assert location.name == "West 1"

      assert :ok = Locations.finish_placement(placement, options)
      assert {:ok, []} = Locations.home(context.fern.id, options)
    end

    test "names a resident or a group, and not both and not neither", context do
      group = Residents.form_group!(%{resident_ids: [context.fern.id]}, context.options)

      for subject <- [%{resident_id: context.fern.id, group_id: group.id}, %{}] do
        assert_raise Ash.Error.Invalid, fn ->
          Ash.Seed.seed!(
            Locations.Placement,
            Map.put(subject, :location_id, context.east.id),
            tenant: context.organisation
          )
        end
      end
    end

    test "puts a group in a location, and its members live there", context do
      options = context.options

      group =
        Residents.form_group!(%{resident_ids: [context.fern.id, context.sage.id]}, options)

      assert {:ok, _} = Locations.settle({:group, group.id}, context.east.id, options)

      assert [{_placement, %{id: id}, members}] = node(context.east.id, options).groups
      assert id == group.id
      assert Enum.map(members, & &1.resident.name) == ["Fern", "Sage"]

      {:ok, [%{location: %{name: "East 1"}, with: with}]} =
        Locations.home(context.sage.id, options)

      assert with.id == group.id
    end

    test "of a resident wins over the placement of its group, while it lasts", context do
      options = context.options

      group =
        Residents.form_group!(%{resident_ids: [context.fern.id, context.sage.id]}, options)

      {:ok, _} = Locations.settle({:group, group.id}, context.east.id, options)
      {:ok, own} = Locations.settle({:resident, context.fern.id}, context.west.id, options)

      # Fern lives in West 1, and East 1 has Sage only.
      assert {:ok, [%{location: %{name: "West 1"}, with: :own}]} =
               Locations.home(context.fern.id, options)

      assert [{_placement, _group, members}] = node(context.east.id, options).groups
      assert Enum.map(members, & &1.resident.name) == ["Sage"]
      assert node(context.east.id, options).count == 1
      assert node(context.west.id, options).count == 1

      # After its own placement ends, Fern is with its group again.
      assert :ok = Locations.finish_placement(own, options)

      assert {:ok, [%{location: %{name: "East 1"}}]} = Locations.home(context.fern.id, options)
      assert node(context.east.id, options).count == 2
    end

    test "counts the residents of a location and of each location inside it", context do
      options = context.options
      group = Residents.form_group!(%{resident_ids: [context.fern.id, context.sage.id]}, options)

      {:ok, _} = Locations.settle({:group, group.id}, context.east.id, options)
      {:ok, _} = Locations.settle({:resident, context.basil.id}, context.west.id, options)

      assert node(context.east.id, options).count == 2
      assert node(context.west.id, options).count == 1
      assert node(context.room.id, options).count == 3
      assert node(context.shed.id, options).count == 3
    end

    test "can go over the capacity of a location, and the housing says so", context do
      options = context.options

      for resident <- [context.fern, context.sage] do
        {:ok, _} = Locations.settle({:resident, resident.id}, context.east.id, options)
      end

      refute node(context.east.id, options).over?

      assert {:ok, _} = Locations.settle({:resident, context.basil.id}, context.east.id, options)
      assert node(context.east.id, options).over?

      # A location with no capacity is never over it.
      refute node(context.room.id, options).over?
    end

    test "can be at the instant that the move happened, which is not after now", context do
      options = context.options
      {:ok, _} = Locations.settle({:resident, context.fern.id}, context.east.id, options)

      first = DateTime.utc_now()
      Process.sleep(5)
      second = DateTime.utc_now()
      Process.sleep(5)

      # The member says later that Fern moved at `second`.
      assert {:ok, _} =
               Locations.settle(
                 {:resident, context.fern.id},
                 context.west.id,
                 [as_of: second] ++ options
               )

      assert names(node(context.east.id, [as_of: first] ++ options).residents) == ["Fern"]
      assert names(node(context.west.id, [as_of: second] ++ options).residents) == ["Fern"]
      assert names(node(context.west.id, options).residents) == ["Fern"]
    end
  end

  describe "the instant that a member gives" do
    test "is a local time of the organisation, and is not after now", context do
      organisation = context.organisation

      assert Rescord.Accounts.instant(organisation, "") == {:ok, nil}
      assert Rescord.Accounts.instant(organisation, nil) == {:ok, nil}

      # Brisbane is 10 hours ahead of UTC.
      assert Rescord.Accounts.instant(organisation, "2026-11-16T08:30") ==
               {:ok, ~U[2026-11-15 22:30:00Z]}

      tomorrow =
        organisation
        |> Rescord.Accounts.today()
        |> Date.add(1)
        |> Date.to_iso8601()

      assert {:error, %InvalidTime{reason: :after_now} = error} =
               Rescord.Accounts.instant(organisation, tomorrow <> "T08:30")

      assert Rescord.Accounts.error_messages(error) == ["The time cannot be after now"]

      assert {:error, %InvalidTime{reason: :not_a_time} = error} =
               Rescord.Accounts.instant(organisation, "yesterday")

      assert Rescord.Accounts.error_messages(error) ==
               ["The time is not a date and a time of this time zone"]
    end
  end
end
