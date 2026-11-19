defmodule Rescord.Accounts.RolesTest do
  @moduledoc """
  Holds the roles of an organisation (ADR 0040): the two roles that each
  organisation has, the roles that its administrators define, the powers
  that a role gives, and the rule that a person gives only the powers that
  their own role has.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures

  alias Rescord.{Accounts, Journal, Tasks}
  alias Rescord.Accounts.{Grants, Role}

  setup do
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
     options: [actor: user, tenant: organisation]}
  end

  defp role(context, key) do
    {:ok, roles} = Accounts.roles(context.admin)
    Enum.find(roles, &(&1.key == key))
  end

  describe "the two roles of each organisation" do
    test "are there from the start, with the powers of ADR 0021", context do
      {:ok, roles} = Accounts.roles(context.options)

      assert Enum.map(roles, &{to_string(&1.name), &1.key}) == [
               {"Administrator", :administrator},
               {"Member", :member}
             ]

      assert role(context, :administrator).powers == Grants.default_powers(:administrator)
      assert role(context, :member).powers == Grants.default_powers(:member)
    end

    test "give the grants that the two roles had in code", context do
      for key <- Grants.roles() do
        record = role(context, key)
        assert Enum.sort(Grants.grants(record)) == Enum.sort(Grants.grants(key))
      end

      # The administrator has each grant of the member, and more.
      member = MapSet.new(Grants.grants(:member))
      administrator = MapSet.new(Grants.grants(:administrator))
      assert MapSet.subset?(member, administrator)
      assert Grants.scope(:administrator, Journal.JournalEntry, :correct) == {:ok, :all}
      assert Grants.scope(:member, Journal.JournalEntry, :correct) == {:ok, :own}
      assert Grants.scope(:member, Tasks.Routine, :start) == :none
      assert Grants.grants(nil) == []
    end

    test "are on each member and on each person who signs in", context do
      {:ok, [_, _] = members} = Accounts.members([load: [:role]] ++ context.admin)
      assert Enum.sort(Enum.map(members, & &1.role.key)) == [:administrator, :member]

      assert %Role{key: :member} =
               Accounts.Checks.Granted.role_of(context.user, context.organisation)
    end

    test "stay: neither one goes", context do
      for key <- Grants.roles() do
        assert {:error, %Ash.Error.Invalid{}} =
                 Accounts.remove_role(role(context, key),
                   actor: context.root,
                   tenant: context.organisation
                 )
      end
    end

    test "keep the change of the roles with the administrators", context do
      administrator = role(context, :administrator)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.revise_role(administrator, %{powers: [:members]}, context.admin)

      assert Accounts.error_messages(error) == [
               "Powers of the administrators keep the change of the roles"
             ]

      assert {:ok, %{name: %Ash.CiString{string: "Coordinator"}}} =
               Accounts.revise_role(administrator, %{name: "Coordinator"}, context.admin)
    end
  end

  describe "a role that an administrator defines" do
    test "has the powers that the administrator ticks, in one order", context do
      assert {:ok, role} =
               Accounts.define_role(
                 %{name: "Feeder", powers: [:stock, :tasks, :tasks]},
                 context.admin
               )

      assert role.powers == [:tasks, :stock]
      assert role.key == nil
      assert Grants.scope(role, Tasks.Task, :complete) == {:ok, :all}
      assert Grants.scope(role, Journal.JournalEntry, :write) == :none

      # Each role reads.
      assert Grants.scope(role, Journal.JournalEntry, :read) == {:ok, :all}
    end

    test "has a name of its own, and a power that Rescord knows", context do
      assert {:ok, _role} = Accounts.define_role(%{name: "Feeder", powers: []}, context.admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.define_role(%{name: "feeder"}, context.admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.define_role(%{name: "Feeder"}, context.admin)

      assert {:error, %Ash.Error.Invalid{}} = Accounts.define_role(%{name: ""}, context.admin)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.define_role(%{name: "Other", powers: [:no_such_power]}, context.admin)
    end

    test "is not a thing that a member defines", context do
      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.define_role(%{name: "Feeder"}, context.options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.revise_role(role(context, :member), %{powers: []}, context.options)
    end

    test "goes when no member has it", context do
      {:ok, feeder} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {:ok, member} = Accounts.set_member_role(context.member, feeder.id, context.admin)

      assert {:error, %Ash.Error.Invalid{} = error} = Accounts.remove_role(feeder, context.admin)
      assert hd(Accounts.error_messages(error)) =~ "is the role of a member"

      {:ok, _member} = Accounts.set_member_role(member, role(context, :member).id, context.admin)

      assert :ok = Accounts.remove_role(feeder, context.admin)
      assert {:ok, nil} = Accounts.role(feeder.id, context.admin)
    end
  end

  describe "a person who gives powers" do
    setup context do
      # A person who changes the members and the roles, and who keeps no
      # journal.
      {:ok, keeper} =
        Accounts.define_role(%{name: "Keeper", powers: [:members, :roles, :tasks]}, context.admin)

      {keeper_member, keeper_user} = member!(context.organisation, :member, context.administrator)
      {:ok, _} = Accounts.set_member_role(keeper_member, keeper.id, context.admin)

      {:ok, keeper: keeper, keeper_options: [actor: keeper_user, tenant: context.organisation]}
    end

    test "gives only the powers that their own role has", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.define_role(%{name: "Writer", powers: [:journal]}, context.keeper_options)

      assert Accounts.error_messages(error) == [
               "Powers gives a power that your role does not have"
             ]

      assert {:ok, _role} =
               Accounts.define_role(%{name: "Planner", powers: [:tasks]}, context.keeper_options)

      # Not to their own role either.
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.revise_role(
                 context.keeper,
                 %{powers: [:members, :roles, :tasks, :journal]},
                 context.keeper_options
               )
    end

    test "gives a member only a role whose powers their own role has", context do
      administrator = role(context, :administrator)

      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.set_member_role(context.member, administrator.id, context.keeper_options)

      assert Accounts.error_messages(error) == ["Role gives a power that your role does not have"]

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.invite_member("new@example.com", %{role_id: administrator.id},
                 actor: context.keeper_options[:actor],
                 tenant: context.organisation
               )

      {:ok, planner} =
        Accounts.define_role(%{name: "Planner", powers: [:tasks]}, context.keeper_options)

      assert {:ok, %{role_id: id}} =
               Accounts.set_member_role(context.member, planner.id, context.keeper_options)

      assert id == planner.id
    end

    test "does not change a member whose role also changes the members", context do
      {other, _user} = member!(context.organisation, :member, context.administrator)
      {:ok, _} = Accounts.set_member_role(other, context.keeper.id, context.admin)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.set_member_role(other, role(context, :member).id, context.keeper_options)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.remove_member(other, context.keeper_options)
    end

    test "names a role of the organisation", context do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.set_member_role(context.member, Ash.UUID.generate(), context.admin)

      assert Accounts.error_messages(error) == ["Role is not a role of this organisation"]
    end
  end

  describe "a root user" do
    test "gives each role, and changes each role", context do
      options = [actor: context.root, tenant: context.organisation]
      administrator = role(context, :administrator)

      assert {:ok, %{role_id: id}} =
               Accounts.set_member_role(context.member, administrator.id, options)

      assert id == administrator.id

      assert {:ok, %{powers: [:roles]}} =
               Accounts.revise_role(administrator, %{powers: [:roles]}, options)
    end
  end
end
