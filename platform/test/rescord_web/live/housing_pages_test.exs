defmodule RescordWeb.HousingPagesTest do
  @moduledoc """
  Holds the pages of the housing: who can open each page, what the tree
  shows, and what a form does. The tests find what a person finds
  (ADR 0107): a location is an article named by its heading, inside the
  article of the location that holds it.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_click: 3]
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Locations, Residents}

  @capacity "Capacity: the number of residents that it houses"

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, member} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    options = [actor: member, tenant: organisation]

    room = Locations.add_location!(%{name: "Long room"}, admin)
    east = Locations.add_location!(%{name: "East 1", parent_id: room.id, capacity: 1}, admin)
    pig = fn name -> resident!(lists, options, %{name: name, sex: :female}) end

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     base: ~p"/o/#{organisation.short_name}",
     admin: admin,
     options: options,
     conn: sign_in(context.conn, member),
     room: room,
     east: east,
     fern: pig.("Fern"),
     sage: pig.("Sage")}
  end

  defp who_lives_here, do: main() |> region("Who lives here")

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    for path <- ["/housing", "/housing/#{context.east.id}"] do
      build_conn() |> sign_in(outsider) |> visit(context.base <> path) |> assert_path("/")
      build_conn() |> visit(context.base <> path) |> assert_path("/")
    end

    context.conn
    |> visit(context.base <> "/housing/#{Ash.UUID.generate()}")
    |> assert_path(context.base <> "/housing")
  end

  describe "the housing page" do
    test "draws a location inside its location, with who lives there", context do
      {:ok, _} = Locations.settle({:resident, context.fern.id}, context.east.id, context.options)
      east = main() |> article("Long room") |> article("East 1")

      context.conn
      |> visit(context.base <> "/housing")
      |> assert_has(main() |> article("Long room") |> heading("Long room", level: 2))
      |> assert_has(east |> heading("East 1", level: 3))
      |> assert_has(east, text: "1 of 1 residents")
      |> assert_has(east |> item(~r/^Fern$/) |> link("Fern"))
      # A member has no form for a new location.
      |> refute_has(button("Add the location"))
    end

    test "says that a location is over its capacity, and that one is free", context do
      context.conn
      |> visit(context.base <> "/housing")
      |> assert_has(~s(article[data-place="free"]), text: "East 1")
      |> refute_has("[data-state=alert]")

      for resident <- [context.fern, context.sage] do
        {:ok, _} = Locations.settle({:resident, resident.id}, context.east.id, context.options)
      end

      context.conn
      |> visit(context.base <> "/housing")
      |> within(
        article("East 1"),
        &assert_has(&1, "[data-state=alert]", text: "Over its capacity")
      )
      |> assert_has(article("East 1"), text: "2 of 1 residents")
    end

    test "lets an administrator add a location inside another", context do
      build_conn()
      |> sign_in(context.administrator)
      |> visit(context.base <> "/housing")
      |> fill_in("Name", with: "West 1")
      |> fill_in(@capacity, with: "2")
      |> select("Inside", option: "Long room")
      |> click_button("Add the location")
      |> assert_has(main() |> article("Long room") |> article("West 1"))
      |> fill_in("Name", with: "")
      |> fill_in(@capacity, with: "0")
      |> click_button("Add the location")
      |> assert_has(main() |> alert(), text: "Name is required")
      |> assert_has(main() |> alert(), text: "Capacity must be")
    end
  end

  describe "the page of a location" do
    setup context do
      {:ok, path: context.base <> "/housing/#{context.east.id}"}
    end

    test "puts a resident there, and ends the placement", context do
      context.conn
      |> visit(context.path)
      |> assert_has(who_lives_here(), text: "Nobody has a placement here.")
      |> click_button("Put here")
      |> assert_has(main() |> alert(), text: "Choose a resident or a group")
      |> select("A resident", option: "Fern")
      |> click_button("Put here")
      |> assert_has(who_lives_here() |> link("Fern"))
      |> assert_has(main(), text: "1 of 1 residents")
      |> click(who_lives_here() |> button("End the placement of Fern"))
      |> assert_has(who_lives_here(), text: "Nobody has a placement here.")
    end

    test "puts a group there, at the time that the move happened", context do
      _group =
        Residents.form_group!(
          %{resident_ids: [context.fern.id, context.sage.id]},
          context.options
        )

      # The form has no seconds, so the test needs a whole second between the
      # group and the time that the member gives.
      Process.sleep(1_100)
      before = DateTime.utc_now()
      Process.sleep(2_100)

      # One second ago, in the time of the organisation.
      at =
        DateTime.utc_now()
        |> DateTime.add(-1, :second)
        |> DateTime.shift_zone!(context.organisation.time_zone)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)
        |> NaiveDateTime.to_iso8601()

      context.conn
      |> visit(context.path)
      |> select("Or a group", option: "Fern and Sage")
      |> fill_in("When the move happened, if not now", with: at)
      |> click_button("Put here")
      |> assert_has(who_lives_here() |> item(~r/^Fern and Sage/), text: "(2 of 2 members here)")
      |> within(main(), &assert_has(&1, "[data-state=alert]", text: "Over its capacity"))

      # The group was not there before the time that the member gave.
      {:ok, tree} = Locations.tree([as_of: before] ++ context.options)
      assert Locations.find(tree, context.east.id).groups == []
    end

    test "says so when the group was not there at the time that the member gives", context do
      group = Residents.form_group!(%{resident_ids: [context.fern.id]}, context.options)

      context.conn
      |> visit(context.path)
      |> select("Or a group", option: "Fern")
      |> fill_in("When the move happened, if not now", with: "2026-01-01T08:00")
      |> click_button("Put here")
      |> assert_has(main() |> alert())

      assert {:ok, nil} = Locations.group_home(group.id, context.options)
    end

    test "refuses a time after now", context do
      tomorrow =
        context.organisation |> Rescord.Accounts.today() |> Date.add(1) |> Date.to_iso8601()

      context.conn
      |> visit(context.path)
      |> select("A resident", option: "Fern")
      |> fill_in("When the move happened, if not now", with: tomorrow <> "T08:00")
      |> click_button("Put here")
      |> assert_has(main() |> alert(), text: "The time cannot be after now")

      assert {:ok, []} = Locations.home(context.fern.id, context.options)
    end

    test "lets an administrator change it, move it and close it, and not a member", context do
      context.conn
      |> visit(context.path)
      |> refute_has(button("Save the location"))
      |> refute_has(button("Move the location"))
      |> refute_has(button("Close the location"))
      # The event that the page does not offer is refused too.
      |> unwrap(&render_click(&1, "close", %{}))
      |> assert_has(main() |> alert())

      conn = build_conn() |> sign_in(context.administrator)

      conn
      |> visit(context.path)
      |> fill_in("Name", with: "East 1a")
      |> fill_in(@capacity, with: "3")
      |> click_button("Save the location")
      |> assert_has(main() |> heading("East 1a", level: 1))
      # The page does not offer the location itself as the one to be inside.
      |> within(field("Inside"), &refute_has(&1, "option", text: "East 1"))
      |> select("Inside", option: "No other location")
      |> click_button("Move the location")

      {:ok, tree} = Locations.tree(context.options)
      assert Enum.map(tree, & &1.location.name) == ["East 1a", "Long room"]

      # A location that holds a resident is not closed, and the page says why.
      {:ok, placement} =
        Locations.settle({:resident, context.fern.id}, context.east.id, context.options)

      conn
      |> visit(context.path)
      |> click(button("Close the location"))
      |> assert_has(main() |> alert(),
        text: "Location has residents or groups in it. Move them first"
      )

      :ok = Locations.finish_placement(placement, context.options)

      conn
      |> visit(context.path)
      |> click(button("Close the location"))
      |> assert_path(context.base <> "/housing")
      |> assert_has(status(), text: "The location is closed.")
      |> refute_has(main() |> article("East 1a"))
    end
  end

  describe "the pages of a resident and of a group" do
    test "say where each lives", context do
      group =
        Residents.form_group!(
          %{resident_ids: [context.fern.id, context.sage.id]},
          context.options
        )

      stay = main() |> region("Stay")
      fern = context.base <> "/residents/#{context.fern.id}"
      east = context.base <> "/housing/#{context.east.id}"

      context.conn
      |> visit(fern)
      |> assert_has(stay, text: "The resident has no place in the housing.")

      {:ok, _} = Locations.settle({:group, group.id}, context.east.id, context.options)

      session = visit(context.conn, fern)
      assert href(session, stay |> link("East 1")) == east
      assert_has(session, stay |> item(~r/^East 1/), text: "(with Fern and Sage)")

      session = visit(context.conn, context.base <> "/groups/#{group.id}")
      assert href(session, main() |> link("East 1")) == east

      {:ok, _} = Locations.settle({:resident, context.fern.id}, context.room.id, context.options)

      context.conn
      |> visit(fern)
      |> assert_has(stay |> item(~r/^Long room/), text: "(a placement of its own)")
    end
  end
end
