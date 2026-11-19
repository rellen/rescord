defmodule RescordWeb.RolePagesTest do
  @moduledoc """
  Holds the page of the roles and the roles on the page of the members
  (ADR 0040): what a member reads, what an administrator changes, the box
  of each power, the role that a person gives a member, and a forged field.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures

  alias Rescord.Accounts
  alias Rescord.Accounts.Grants
  alias RescordWeb.RoleWords

  setup context do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {member, user} = member!(organisation, :member, administrator)

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     user: user,
     admin: [actor: administrator, tenant: organisation],
     path: ~p"/o/#{organisation.short_name}/roles",
     members_path: ~p"/o/#{organisation.short_name}/members",
     conn: sign_in(context.conn, administrator)}
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

  defp role(context, key) do
    {:ok, roles} = Accounts.roles(context.admin)
    Enum.find(roles, &(&1.key == key))
  end

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(outsider) |> live(context.path)

    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.path)
  end

  describe "the roles" do
    test "are on the page of a member, with what each may do, and no form", context do
      {view, html} = open(build_conn() |> sign_in(context.user), context.path)

      assert has_element?(view, "h3", "Administrator")
      assert has_element?(view, "h3", "Member")
      assert html =~ RoleWords.power(:routines)
      assert has_element?(view, "small", "1 member has this role.")
      refute has_element?(view, "#new-role")
      refute has_element?(view, "form")

      # An event that the page did not offer is refused.
      render_submit(view, "define", %{"role" => %{"name" => "Feeder"}})
      assert has_element?(view, "main p[role=alert]")
      assert {:ok, [_, _]} = Accounts.roles(context.admin)
    end

    test "has a box for each power, in the fieldset of its area" do
      keys = for {_area, powers} <- RoleWords.areas(), power <- powers, do: power

      assert Enum.sort(keys) == Enum.sort(Grants.power_keys())
      assert length(keys) == length(Enum.uniq(keys))
      assert Enum.sort(Map.keys(Grants.powers())) == Enum.sort(Grants.power_keys())
      for key <- keys, do: assert(is_binary(RoleWords.power(key)))
    end
  end

  describe "a new role" do
    test "has the name and the powers of the form", context do
      {view, _html} = open(context.conn, context.path)

      {view, html} =
        submit(view, context.conn, "#define", role: %{name: "Feeder", powers: ["tasks", "stock"]})

      assert has_element?(view, "h3", "Feeder")
      assert html =~ RoleWords.power(:tasks)
      assert has_element?(view, "small", "No member has this role.")

      {:ok, roles} = Accounts.roles(context.admin)
      assert %{powers: [:tasks, :stock]} = Enum.find(roles, &(to_string(&1.name) == "Feeder"))
    end

    test "says what is wrong in the form, which stays open with what was typed", context do
      {view, _html} = open(context.conn, context.path)

      html =
        view
        |> form("#define", role: %{name: "Member", powers: ["tasks"]})
        |> render_submit()

      assert has_element?(view, "#new-role[open] p[role=alert]", "is the name of another role")
      assert html =~ ~s(value="Member")
      assert has_element?(view, "#define input[value=tasks][checked]")
    end

    test "takes no power that Rescord does not know, and no forged field", context do
      {view, _html} = open(context.conn, context.path)

      {:error, {:live_redirect, _to}} =
        render_submit(view, "define", %{
          "role" => %{"name" => "Odd", "powers" => ["tasks", "no_such_power", %{"a" => "map"}]}
        })

      {:ok, roles} = Accounts.roles(context.admin)
      assert %{powers: [:tasks]} = Enum.find(roles, &(to_string(&1.name) == "Odd"))
    end
  end

  describe "a role on the page" do
    test "changes, and the change is refused for the administrators without the roles",
         context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {view, _html} = open(context.conn, context.path)

      {view, _html} =
        submit(view, context.conn, "#revise-#{feeder.id}",
          role: %{name: "Feeder", powers: ["tasks", "journal"]}
        )

      assert {:ok, %{powers: [:journal, :tasks]}} = Accounts.role(feeder.id, context.admin)

      administrator = role(context, :administrator)

      view
      |> form("#revise-#{administrator.id}", role: %{name: "Administrator", powers: ["tasks"]})
      |> render_submit()

      assert has_element?(
               view,
               "#revise-details-#{administrator.id}[open] p[role=alert]",
               "keep the change of the roles"
             )
    end

    test "goes when no member has it, and the two of each organisation have no button",
         context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {view, _html} = open(context.conn, context.path)

      refute has_element?(view, "#role-#{role(context, :member).id} button", "Remove")
      assert has_element?(view, "#role-#{feeder.id} button", "Remove")

      {:ok, view, _html} =
        view |> render_click("remove", %{"id" => feeder.id}) |> follow_redirect(context.conn)

      refute has_element?(view, "h3", "Feeder")
    end
  end

  describe "the role of a member" do
    test "is on the page of the members, and an administrator gives another one", context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {view, html} = open(context.conn, context.members_path)

      assert html =~ "Member"

      view
      |> form("#role-of-#{context.member.id}", member_role: %{role_id: feeder.id})
      |> render_submit()

      assert {:ok, %{role_id: id}} = Accounts.member(context.member.id, context.admin)
      assert id == feeder.id
    end

    test "is chosen in the invitation, among the roles that the person can give", context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {view, _html} = open(context.conn, context.members_path)

      assert has_element?(view, "#invite_role_id option", "Feeder")

      view
      |> form("#invite", invite: %{email: "fern@example.com", role_id: feeder.id})
      |> render_submit()

      user = Accounts.user_by_email!("fern@example.com", authorize?: false)
      {:ok, members} = Accounts.members(context.admin)
      assert Enum.find(members, &(&1.user_id == user.id)).role_id == feeder.id
    end
  end
end
