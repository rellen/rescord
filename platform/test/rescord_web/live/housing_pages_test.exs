defmodule RescordWeb.HousingPagesTest do
  @moduledoc """
  Holds the pages of the housing: who can open each page, what the tree
  shows, and what a form does.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Locations, Residents}

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

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp submit(view, conn, selector, fields) do
    {:ok, view, _html} =
      view |> form(selector, fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  defp press(view, conn, event, params) do
    {:ok, view, _html} = view |> render_click(event, params) |> follow_redirect(conn)
    {view, render_async(view)}
  end

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    for path <- ["/housing", "/housing/#{context.east.id}"] do
      assert {:error, {:redirect, %{to: "/"}}} =
               build_conn() |> sign_in(outsider) |> live(context.base <> path)

      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.base <> path)
    end

    assert {:error, {:redirect, %{to: to}}} =
             live(context.conn, context.base <> "/housing/#{Ash.UUID.generate()}")

    assert to == context.base <> "/housing"
  end

  describe "the housing page" do
    test "draws a location inside its location, with who lives there", context do
      {:ok, _} = Locations.settle({:resident, context.fern.id}, context.east.id, context.options)

      {view, html} = open(context.conn, context.base <> "/housing")

      assert has_element?(view, "article[data-place] article[data-place] h3 a", "East 1")
      assert has_element?(view, "article[data-place] > header h2 a", "Long room")
      assert html =~ "1 of 1 residents"
      assert has_element?(view, "article[data-place] article[data-place] li a", "Fern")

      # A member has no form for a new location.
      refute has_element?(view, "#location")
    end

    test "says that a location is over its capacity, and that one is free", context do
      {view, _html} = open(context.conn, context.base <> "/housing")
      assert has_element?(view, ~s(article[data-place="free"]), "East 1")
      refute has_element?(view, "[data-state=alert]")

      for resident <- [context.fern, context.sage] do
        {:ok, _} = Locations.settle({:resident, resident.id}, context.east.id, context.options)
      end

      {view, html} = open(context.conn, context.base <> "/housing")
      assert has_element?(view, "[data-state=alert]", "Over its capacity")
      assert html =~ "2 of 1 residents"
    end

    test "lets an administrator add a location inside another", context do
      conn = build_conn() |> sign_in(context.administrator)
      {view, _html} = open(conn, context.base <> "/housing")

      {view, _html} =
        submit(view, conn, "#location",
          location: %{name: "West 1", capacity: "2", parent_id: context.room.id}
        )

      assert has_element?(view, "article[data-place] article[data-place] h3 a", "West 1")

      view |> form("#location", location: %{name: "", capacity: "0"}) |> render_submit()
      assert has_element?(view, "main p[role=alert]", "Name is required")
      assert has_element?(view, "main p[role=alert]", "Capacity must be")
    end
  end

  describe "the page of a location" do
    setup context do
      {:ok, path: context.base <> "/housing/#{context.east.id}"}
    end

    test "puts a resident there, and ends the placement", context do
      {view, html} = open(context.conn, context.path)
      assert html =~ "Nobody has a placement here."

      html = view |> form("#placement", placement: %{resident_id: ""}) |> render_submit()
      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Choose a resident or a group"

      {view, html} =
        submit(view, context.conn, "#placement", placement: %{resident_id: context.fern.id})

      assert html =~ "Fern"
      assert html =~ "1 of 1 residents"

      {:ok, [%{placement: placement}]} = Locations.home(context.fern.id, context.options)
      {_view, html} = press(view, context.conn, "finish", %{"id" => placement.id})
      assert html =~ "Nobody has a placement here."
    end

    test "puts a group there, at the time that the move happened", context do
      group =
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

      {view, _html} = open(context.conn, context.path)

      {_view, html} =
        submit(view, context.conn, "#placement", placement: %{group_id: group.id, at: at})

      assert html =~ "Fern and Sage"
      assert html =~ "(2 of 2 members here)"
      assert html =~ "Over its capacity"

      # The group was not there before the time that the member gave.
      {:ok, tree} = Locations.tree([as_of: before] ++ context.options)
      assert Locations.find(tree, context.east.id).groups == []
    end

    test "says so when the group was not there at the time that the member gives", context do
      group = Residents.form_group!(%{resident_ids: [context.fern.id]}, context.options)
      {view, _html} = open(context.conn, context.path)

      view
      |> form("#placement", placement: %{group_id: group.id, at: "2026-01-01T08:00"})
      |> render_submit()

      assert has_element?(view, "main p[role=alert]")
      assert {:ok, nil} = Locations.group_home(group.id, context.options)
    end

    test "refuses a time after now", context do
      {view, _html} = open(context.conn, context.path)

      tomorrow =
        context.organisation |> Rescord.Accounts.today() |> Date.add(1) |> Date.to_iso8601()

      html =
        view
        |> form("#placement",
          placement: %{resident_id: context.fern.id, at: tomorrow <> "T08:00"}
        )
        |> render_submit()

      assert has_element?(view, "main p[role=alert]")
      assert html =~ "The time cannot be after now"
      assert {:ok, []} = Locations.home(context.fern.id, context.options)
    end

    test "lets an administrator change it, move it and close it, and not a member", context do
      {view, _html} = open(context.conn, context.path)
      refute has_element?(view, "#location")
      refute has_element?(view, "#move")

      render_click(view, "close", %{})
      assert has_element?(view, "main p[role=alert]")

      conn = build_conn() |> sign_in(context.administrator)
      {view, _html} = open(conn, context.path)

      {view, html} = submit(view, conn, "#location", location: %{name: "East 1a", capacity: "3"})
      assert html =~ "East 1a"

      # The page does not offer the location itself as the one to be inside.
      refute has_element?(view, ~s(#move option[value="#{context.east.id}"]))

      {_view, _html} = submit(view, conn, "#move", move: %{parent_id: ""})
      {:ok, tree} = Locations.tree(context.options)
      assert Enum.map(tree, & &1.location.name) == ["East 1a", "Long room"]

      # A location that holds a resident is not closed, and the page says why.
      {:ok, placement} =
        Locations.settle({:resident, context.fern.id}, context.east.id, context.options)

      {view, _html} = open(conn, context.path)
      render_click(view, "close", %{})

      assert has_element?(
               view,
               "main p[role=alert]",
               "Location has residents or groups in it. Move them first"
             )

      :ok = Locations.finish_placement(placement, context.options)
      {view, _html} = open(conn, context.path)
      {_view, html} = press(view, conn, "close", %{})
      assert html =~ "The location is closed."
      refute html =~ "East 1a"
    end
  end

  describe "the pages of a resident and of a group" do
    test "say where each lives", context do
      group =
        Residents.form_group!(
          %{resident_ids: [context.fern.id, context.sage.id]},
          context.options
        )

      {_view, html} = open(context.conn, context.base <> "/residents/#{context.fern.id}")
      assert html =~ "The resident has no place in the housing."

      {:ok, _} = Locations.settle({:group, group.id}, context.east.id, context.options)

      {view, html} = open(context.conn, context.base <> "/residents/#{context.fern.id}")

      assert has_element?(
               view,
               ~s(a[href="#{context.base}/housing/#{context.east.id}"]),
               "East 1"
             )

      assert html =~ "(with Fern and Sage)"

      {view, _html} = open(context.conn, context.base <> "/groups/#{group.id}")

      assert has_element?(
               view,
               ~s(dd a[href="#{context.base}/housing/#{context.east.id}"]),
               "East 1"
             )

      {:ok, _} = Locations.settle({:resident, context.fern.id}, context.room.id, context.options)
      {_view, html} = open(context.conn, context.base <> "/residents/#{context.fern.id}")
      assert html =~ "(a placement of its own)"
      assert html =~ "Long room"
    end
  end
end
