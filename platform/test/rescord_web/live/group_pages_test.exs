defmodule RescordWeb.GroupPagesTest do
  @moduledoc """
  Holds the pages of the groups, and the family and groups part of the page
  of a resident: who can open each page, and what a form does.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.Residents

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, member} = member!(organisation, :member, root)
    lists = lists!(organisation, root)
    options = [actor: member, tenant: organisation]
    pig = fn name, sex -> resident!(lists, options, %{name: name, sex: sex}) end

    {:ok,
     root: root,
     organisation: organisation,
     member: member,
     base: ~p"/o/#{organisation.short_name}",
     options: options,
     conn: sign_in(context.conn, member),
     fern: pig.("Fern", :female),
     sage: pig.("Sage", :female),
     basil: pig.("Basil", :male)}
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

  defp sisters!(context) do
    litter = Residents.name_family!("The spring litter", context.options)

    for resident <- [context.fern, context.sage] do
      Residents.add_to_family!(%{resident_id: resident.id, family_id: litter.id}, context.options)
    end

    litter
  end

  test "the pages do not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)
    group = Residents.form_group!(%{resident_ids: [context.fern.id]}, context.options)

    for path <- ["/groups", "/groups/#{group.id}"] do
      assert {:error, {:redirect, %{to: "/"}}} =
               build_conn() |> sign_in(outsider) |> live(context.base <> path)

      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.base <> path)
    end

    assert {:error, {:redirect, %{to: to}}} =
             live(context.conn, context.base <> "/groups/#{Ash.UUID.generate()}")

    assert to == context.base <> "/groups"
  end

  describe "the groups page" do
    test "makes a group with its first members, and lists it with its words", context do
      sisters!(context)
      {view, html} = open(context.conn, context.base <> "/groups")
      assert html =~ "There is no group yet."

      {_view, html} =
        submit(view, context.conn, "#group",
          group: %{name: "", resident_ids: [context.fern.id, context.sage.id, context.basil.id]}
        )

      # The page of the new group.
      assert html =~ "Basil, Fern and Sage"
      assert html =~ "Sisters and an unrelated male"

      {_view, html} = open(context.conn, context.base <> "/groups")
      assert html =~ "Basil, Fern and Sage"
      assert html =~ "Sisters and an unrelated male"
      refute html =~ "There is no group yet."
    end
  end

  describe "the page of a group" do
    setup context do
      sisters!(context)

      group =
        Residents.form_group!(
          %{resident_ids: [context.fern.id, context.sage.id]},
          context.options
        )

      {:ok, group: group, path: context.base <> "/groups/#{group.id}"}
    end

    test "adds a member and takes one out, and the words follow", context do
      {view, html} = open(context.conn, context.path)
      assert html =~ "Fern and Sage"
      assert html =~ "Sisters"

      {view, html} =
        submit(view, context.conn, "#member", member: %{resident_id: context.basil.id})

      assert html =~ "Sisters and an unrelated male"
      # Each resident is in the group now, so there is nobody to add.
      refute has_element?(view, "#member")

      {:ok, %{members: members}} = Residents.group_with_facts(context.group.id, context.options)
      fern = Enum.find(members, &(&1.resident.name == "Fern"))

      {view, html} = press(view, context.conn, "leave", %{"id" => fern.id})
      assert html =~ "Basil and Sage"
      assert html =~ "No relation is recorded"

      # A member that is not one of this group does nothing.
      render_click(view, "leave", %{"id" => Ash.UUID.generate()})
      refute has_element?(view, "main p[role=alert]")
      assert render(view) =~ "Basil and Sage"
    end

    test "takes a name and the words of a member, and gives the words of Rescord again",
         context do
      {view, _html} = open(context.conn, context.path)

      {view, html} =
        submit(view, context.conn, "#group",
          group: %{name: "The East 1 pair", description: "Bonded at intake"}
        )

      assert html =~ "The East 1 pair"
      assert html =~ "Bonded at intake"
      assert html =~ "(the words of a member)"

      {_view, html} = submit(view, context.conn, "#group", group: %{description: ""})
      assert html =~ "Sisters"
      refute html =~ "(the words of a member)"
    end

    test "closes the group", context do
      {view, _html} = open(context.conn, context.path)
      {_view, html} = press(view, context.conn, "close", %{})

      assert html =~ "The group is closed."
      assert html =~ "There is no group yet."
    end
  end

  describe "the family and groups of a resident" do
    setup context do
      {:ok, path: context.base <> "/residents/#{context.fern.id}"}
    end

    test "adds a parent and removes it, and the parent shows its young", context do
      {view, html} = open(context.conn, context.path)
      assert html =~ "No parent is recorded."

      {view, html} =
        submit(view, context.conn, "#parent",
          parent: %{parent_id: context.basil.id, role: "father"}
        )

      assert html =~ "Father:"
      assert html =~ ~s(aria-label="Remove the father Basil")

      {_view, html} = open(context.conn, context.base <> "/residents/#{context.basil.id}")
      assert html =~ "Young"
      assert html =~ "Fern"

      # A resident is not a parent of its own parent.
      {basil_view, _html} = open(context.conn, context.base <> "/residents/#{context.basil.id}")

      html =
        basil_view
        |> form("#parent", parent: %{parent_id: context.fern.id, role: "mother"})
        |> render_submit()

      assert has_element?(basil_view, "main p[role=alert]")
      assert html =~ "is one of the young of this resident"

      %{parents: [link]} = Residents.relations(context.fern.id, context.options)
      {_view, html} = press(view, context.conn, "remove_parent", %{"id" => link.id})
      assert html =~ "No parent is recorded."
    end

    test "adds the resident to a new family and to one that is there", context do
      {view, html} = open(context.conn, context.path)
      assert html =~ "The resident is in no family."

      html = view |> form("#family", family: %{name: ""}) |> render_submit()
      assert has_element?(view, "main p[role=alert]")
      assert html =~ "Choose a family, or give a new one a name"

      {_view, html} = submit(view, context.conn, "#family", family: %{name: "The spring litter"})
      assert html =~ "The spring litter"

      # The page of another resident offers the family that is there now.
      {view, _html} = open(context.conn, context.base <> "/residents/#{context.sage.id}")
      [family] = Residents.families!(context.options)

      {_view, html} = submit(view, context.conn, "#family", family: %{family_id: family.id})
      assert html =~ "The spring litter"

      assert [_one] = Residents.families!(context.options)
    end

    test "shows the groups of the resident with their words", context do
      sisters!(context)
      Residents.form_group!(%{resident_ids: [context.fern.id, context.sage.id]}, context.options)

      {_view, html} = open(context.conn, context.path)
      assert html =~ "Fern and Sage"
      assert html =~ "Sisters"
    end
  end
end
