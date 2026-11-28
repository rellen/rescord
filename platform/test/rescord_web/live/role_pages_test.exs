defmodule RescordWeb.RolePagesTest do
  @moduledoc """
  Holds the page of the roles and the roles on the page of the members
  (ADR 0040): what a member reads, what an administrator changes, the box
  of each power, the role that a person gives a member, and a forged field.
  The tests find what a person finds (ADR 0107): a role is the article of
  its name in the region "The roles".

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_async: 1, render_submit: 3]
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

  defp role(context, key) do
    {:ok, roles} = Accounts.roles(context.admin)
    Enum.find(roles, &(&1.key == key))
  end

  defp card(name), do: main() |> region("The roles") |> article(name)
  defp new_role, do: main() |> details("New role")
  defp change(name), do: card(name) |> details("Change the role #{name}")

  test "the page does not open for a user of another organisation, or with no sign-in", context do
    other = organisation!(context.root, "Other")
    {_, outsider} = member!(other, :administrator, context.root)

    build_conn() |> sign_in(outsider) |> visit(context.path) |> assert_path("/")
    build_conn() |> visit(context.path) |> assert_path("/")
  end

  describe "the roles" do
    test "are on the page of a member, with what each may do, and no form", context do
      build_conn()
      |> sign_in(context.user)
      |> visit(context.path)
      |> assert_has(card("Administrator") |> item(RoleWords.power(:routines)))
      |> assert_has(card("Member"), text: "1 member has this role.")
      |> refute_has(new_role())
      |> refute_has(main() |> field(~r/./))
      # An event that the page did not offer is refused.
      |> unwrap(&render_submit(&1, "define", %{"role" => %{"name" => "Feeder"}}))
      |> assert_has(main() |> alert())

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
      context.conn
      |> visit(context.path)
      |> within(new_role(), fn form ->
        form
        |> fill_in("Name", with: "Feeder")
        |> check(RoleWords.power(:tasks))
        |> check(RoleWords.power(:stock))
        |> click_button("Add the role")
      end)
      |> assert_has(card("Feeder") |> item(RoleWords.power(:tasks)))
      |> assert_has(card("Feeder"), text: "No member has this role.")

      {:ok, roles} = Accounts.roles(context.admin)
      assert %{powers: [:tasks, :stock]} = Enum.find(roles, &(to_string(&1.name) == "Feeder"))
    end

    test "says what is wrong in the form, which stays open with what was typed", context do
      session =
        context.conn
        |> visit(context.path)
        |> within(new_role(), fn form ->
          form
          |> fill_in("Name", with: "Member")
          |> check(RoleWords.power(:tasks))
          |> click_button("Add the role")
        end)
        |> assert_has(new_role() |> alert(), text: "is the name of another role")

      assert open?(session, new_role())
      assert value(session, new_role() |> field("Name")) == "Member"
      assert checked?(session, new_role() |> field(RoleWords.power(:tasks)))
      refute checked?(session, new_role() |> field(RoleWords.power(:stock)))
    end

    test "takes no power that Rescord does not know, and no forged field", context do
      context.conn
      |> visit(context.path)
      |> unwrap(
        &render_submit(&1, "define", %{
          "role" => %{"name" => "Odd", "powers" => ["tasks", "no_such_power", %{"a" => "map"}]}
        })
      )
      |> assert_has(card("Odd"))

      {:ok, roles} = Accounts.roles(context.admin)
      assert %{powers: [:tasks]} = Enum.find(roles, &(to_string(&1.name) == "Odd"))
    end
  end

  describe "a role on the page" do
    test "changes, and the change is refused for the administrators without the roles",
         context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)

      session =
        context.conn
        |> visit(context.path)
        |> within(change("Feeder"), fn form ->
          form |> check(RoleWords.power(:journal)) |> click_button("Save the role Feeder")
        end)

      assert {:ok, %{powers: [:journal, :tasks]}} = Accounts.role(feeder.id, context.admin)

      session =
        session
        |> within(change("Administrator"), fn form ->
          form
          |> uncheck(RoleWords.power(:roles))
          |> click_button("Save the role Administrator")
        end)
        |> assert_has(change("Administrator") |> alert(), text: "keep the change of the roles")

      assert open?(session, change("Administrator"))
    end

    test "goes when no member has it, and the two of each organisation have no button",
         context do
      Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)

      context.conn
      |> visit(context.path)
      |> refute_has(card("Member") |> button("Remove the role Member"))
      |> refute_has(card("Administrator") |> button("Remove the role Administrator"))
      |> click(card("Feeder") |> button("Remove the role Feeder"))
      |> refute_has(card("Feeder"))

      assert role(context, :member)
    end
  end

  describe "the role of a member" do
    test "is on the page of the members, and an administrator gives another one", context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      email = to_string(context.user.email)
      member = main() |> row(~r/^#{Regex.escape(email)}\b/)

      session = context.conn |> visit(context.members_path) |> unwrap(&render_async/1)
      assert value(session, member |> field("The role of #{email}")) == "Member"

      session
      |> select("The role of #{email}", option: "Feeder")
      |> click(member |> button("Give the role to #{email}"))

      assert {:ok, %{role_id: id}} = Accounts.member(context.member.id, context.admin)
      assert id == feeder.id
    end

    test "is chosen in the invitation, among the roles that the person can give", context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      invite = main() |> region("Invite a person")

      context.conn
      |> visit(context.members_path)
      |> unwrap(&render_async/1)
      |> within(invite |> field("Role"), &assert_has(&1, "option", text: "Feeder"))
      |> within(invite, fn form ->
        form
        |> fill_in("Email address", with: "fern@example.com")
        |> select("Role", option: "Feeder")
        |> click_button("Send the invitation")
      end)

      user = Accounts.user_by_email!("fern@example.com", authorize?: false)
      {:ok, members} = Accounts.members(context.admin)
      assert Enum.find(members, &(&1.user_id == user.id)).role_id == feeder.id
    end
  end
end
