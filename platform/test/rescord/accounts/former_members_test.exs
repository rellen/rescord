defmodule Rescord.Accounts.FormerMembersTest do
  @moduledoc """
  Holds what the removal of a member does (ADR 0105, issue 31, level 1):

    * the records of a former member stay theirs, and each page names them
      "email (former member)";
    * a root user who is not a member is "Rescord operator";
    * the tasks that are due and the routines let go of the person, and a
      task left with nobody is for anybody;
    * the calendar feeds of the person are revoked;
    * the last member who can change the members stays;
    * an invitation that waits is not sent to a person who was removed.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Swoosh.TestAssertions

  alias Rescord.{Accounts, Calendars, Tasks}

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {member, user} = member!(organisation, :member, administrator)
    {_, other} = member!(organisation, :member, administrator)
    send_invitations()

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     user: user,
     other: other,
     admin: [actor: administrator, tenant: organisation],
     options: [actor: user, tenant: organisation],
     soon: DateTime.add(DateTime.utc_now(), 1, :hour) |> DateTime.truncate(:second)}
  end

  defp remove!(context), do: :ok = Accounts.remove_member(context.member, context.admin)

  describe "the people of an organisation" do
    test "name a member by the email address", context do
      people = Accounts.people(context.admin)

      assert people[context.user.id] == %{label: to_string(context.user.email), state: :member}
    end

    test "name a removed member as a former member", context do
      remove!(context)

      assert Accounts.people(context.admin)[context.user.id] ==
               %{label: "#{context.user.email} (former member)", state: :former}

      assert Accounts.labels(context.admin)[context.user.id] ==
               "#{context.user.email} (former member)"
    end

    test "name a person who is a member again as a member", context do
      remove!(context)
      member!(context.organisation, :member, context.administrator, to_string(context.user.email))

      assert Accounts.people(context.admin)[context.user.id].state == :member
    end

    test "name a root user who is not a member as the operator, except to that root user",
         context do
      assert Accounts.people(context.admin)[context.root.id] ==
               %{label: "Rescord operator", state: :operator}

      assert Accounts.labels(actor: context.root, tenant: context.organisation)[context.root.id] ==
               to_string(context.root.email)
    end
  end

  describe "the former members" do
    test "are the removed members who are not members again", context do
      assert Accounts.former_members(context.admin) == []

      remove!(context)
      assert [former] = Accounts.former_members(context.admin)
      assert former.user_id == context.user.id
      assert to_string(former.email) == to_string(context.user.email)

      member!(context.organisation, :member, context.administrator, to_string(context.user.email))
      assert Accounts.former_members(context.admin) == []
    end

    test "are in members.csv of the export, marked as former", context do
      remove!(context)

      {:ok, members} = Accounts.members_with_former([load: [:former?]] ++ context.admin)
      assert Enum.find(members, &(&1.user_id == context.user.id)).former?
    end
  end

  describe "a removal" do
    test "takes the person out of the tasks that are due, and keeps a task that is done",
         context do
      shared =
        Tasks.plan_task!(
          %{
            title: "Hay",
            due_at: context.soon,
            assignee_ids: [context.user.id, context.other.id]
          },
          context.admin
        )

      alone =
        Tasks.plan_task!(
          %{title: "Pellets", due_at: context.soon, assignee_ids: [context.user.id]},
          context.admin
        )

      done =
        Tasks.plan_task!(
          %{title: "Water", due_at: context.soon, assignee_ids: [context.user.id]},
          context.admin
        )

      Tasks.complete_task!(done, %{}, context.options)

      remove!(context)

      assert Tasks.task!(shared.id, context.admin).assignee_ids == [context.other.id]
      # A task left with nobody is for anybody.
      assert Tasks.task!(alone.id, context.admin).assignee_ids == []
      assert Tasks.task!(done.id, context.admin).assignee_ids == [context.user.id]
    end

    test "takes the person out of each routine", context do
      routine =
        Tasks.start_routine!(
          %{
            title: "Hay",
            pattern: :daily,
            times: [~T[23:59:00]],
            starts_on: Accounts.today(context.organisation),
            assignee_ids: [context.user.id, context.other.id]
          },
          context.admin
        )

      remove!(context)

      assert Tasks.routine!(routine.id, context.admin).assignee_ids == [context.other.id]
    end

    test "revokes the calendar feeds of the person", context do
      feed = Calendars.subscribe!(%{name: "My phone"}, context.options)

      remove!(context)

      {:ok, feeds} = Calendars.feeds(actor: context.root, tenant: context.organisation)
      refute Enum.any?(feeds, &(&1.id == feed.id))
    end

    test "does not take out the last member who can change the members", context do
      {:ok, members} = Accounts.members(actor: context.root, tenant: context.organisation)
      administrator = Enum.find(members, &(&1.user_id == context.administrator.id))

      assert {:error, %Ash.Error.Invalid{} = error} =
               Accounts.remove_member(administrator,
                 actor: context.root,
                 tenant: context.organisation
               )

      assert Exception.message(error) =~ "the last member who can change the members"

      # With a second administrator, a root user removes the first.
      member!(context.organisation, :administrator, context.root)

      assert :ok =
               Accounts.remove_member(administrator,
                 actor: context.root,
                 tenant: context.organisation
               )
    end

    test "stops an invitation that waits", context do
      {member, user} = member!(context.organisation, :member, context.administrator)
      :ok = Accounts.remove_member(member, context.admin)

      assert %{success: 1} = send_invitations()
      refute_email_sent(to: [{"", to_string(user.email)}])
    end
  end
end
