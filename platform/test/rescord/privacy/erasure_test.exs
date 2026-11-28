defmodule Rescord.Privacy.ErasureTest do
  @moduledoc """
  Holds what an erasure on request does (ADR 0105, issue 31, level 2):

    * the member becomes Former member N, with the next number, and each
      page names them so;
    * a member is removed first, and their tasks let go of them;
    * the money records hold the email until the end of the money period;
    * the conversations with Ruby go, and the calendar feeds lose their
      names, also in their versions;
    * with no membership left, the account loses its email, its tokens and
      its versions' email, and each job that names the email goes;
    * the request is done, keeps what was kept, and a job sends the email;
    * only a root user erases a member who can change the members;
    * a marker in the store erases the person again after a restore.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures
  import Rescord.StorageFixtures
  import Swoosh.TestAssertions

  alias Rescord.{Accounts, Calendars, Expenses, Privacy, Repo, Storage, Tasks}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    disk_store!(tmp_dir)
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {member, user} = member!(organisation, :member, administrator)
    send_invitations()
    flush_emails()

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     member: member,
     user: user,
     admin: [actor: administrator, tenant: organisation],
     options: [actor: user, tenant: organisation]}
  end

  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  defp request!(context, more \\ %{}) do
    Privacy.record_request!(
      Map.merge(
        %{
          member_id: context.member.id,
          how_received: :email,
          identity: "Replied from the address"
        },
        more
      ),
      context.admin
    )
  end

  defp erase!(context, choices \\ %{}, request \\ nil) do
    {:ok, done} = Privacy.erase(request || request!(context), choices, context.admin)
    done
  end

  defp erased_member(context) do
    {:ok, member} =
      Accounts.member_with_former(context.member.id,
        tenant: context.organisation,
        authorize?: false
      )

    member
  end

  defp user(context), do: Ash.get!(Accounts.User, context.user.id, authorize?: false)

  describe "an erasure" do
    test "makes the member Former member N, with the next number of the organisation", context do
      done = erase!(context)

      member = erased_member(context)
      assert member.former_number == 1
      assert member.archived_at
      assert member.erased_at
      assert done.state == :done
      assert done.former_number == 1
      assert done.correlation_id

      assert Accounts.labels(context.admin)[context.user.id] == "Former member 1"
      assert Accounts.former_members(context.admin) == []

      {other_member, other} = member!(context.organisation, :member, context.administrator)
      erase!(%{context | member: other_member, user: other})
      assert Accounts.labels(context.admin)[other.id] == "Former member 2"
    end

    test "takes the person out of the tasks that are due", context do
      soon = DateTime.add(DateTime.utc_now(), 1, :hour) |> DateTime.truncate(:second)

      task =
        Tasks.plan_task!(
          %{title: "Hay", due_at: soon, assignee_ids: [context.user.id]},
          context.admin
        )

      erase!(context)

      assert Tasks.task!(task.id, context.admin).assignee_ids == []
    end

    test "renames the calendar feeds and redacts their old names", context do
      feed = Calendars.subscribe!(%{name: "Kim's phone"}, context.options)

      erase!(context)

      [row] =
        Repo.query!(
          "SELECT name FROM \"org_#{context.organisation.id}\".calendar_feeds WHERE id = $1",
          [Ecto.UUID.dump!(feed.id)]
        ).rows

      assert row == ["Feed of former member 1"]

      %{rows: names} =
        Repo.query!(
          "SELECT changes->>'name' FROM \"org_#{context.organisation.id}\".calendar_feeds_versions WHERE version_source_id = $1 AND changes ? 'name'",
          [Ecto.UUID.dump!(feed.id)]
        )

      refute ["Kim's phone"] in names
    end

    test "erases the account when no membership is left", context do
      token_subject = AshAuthentication.user_to_subject(context.user)
      erase!(context)

      user = user(context)
      assert is_nil(user.email)
      assert user.erased_at

      %{rows: [[0]]} =
        Repo.query!("SELECT count(*) FROM tokens WHERE subject = $1", [token_subject])

      %{rows: emails} =
        Repo.query!(
          "SELECT changes->>'email' FROM users_versions WHERE version_source_id = $1 AND changes ? 'email'",
          [Ecto.UUID.dump!(user.id)]
        )

      assert Enum.all?(emails, &(&1 in [["REDACTED"], [nil]]))
    end

    test "keeps the account of a person who is a member of another organisation", context do
      elsewhere = organisation!(context.root, "Banksia Rescue")
      member!(elsewhere, :member, context.root, to_string(context.user.email))

      erase!(context)

      assert to_string(user(context).email) == to_string(context.user.email)
      # The person is not invited here again with the same account.
      assert {:error, error} =
               Accounts.invite_member(to_string(context.user.email), context.admin)

      assert Exception.message(error) =~ "was erased from this organisation"
    end

    test "holds the email for the money records, for the pages of the expenses", context do
      lists = lists!(context.organisation, context.root)

      Expenses.record_expense!(
        %{
          paid_by: :member,
          payer_id: context.user.id,
          amount: "12.00",
          incurred_on: Accounts.today(context.organisation),
          payee: "Produce shop",
          description: "Hay",
          category_id: lists.expense_category.veterinary
        },
        context.admin
      )

      done = erase!(context)

      member = erased_member(context)
      until = Date.shift(Accounts.today(context.organisation), year: 7)
      assert member.held_until == until
      assert done.kept =~ "money records"

      assert Accounts.labels(context.admin)[context.user.id] == "Former member 1"

      assert Accounts.labels(context.admin, held: true)[context.user.id] =~
               to_string(context.user.email)

      assert Accounts.labels(context.admin, held: true)[context.user.id] =~
               "held for the money records"
    end

    test "sends the email of the outcome, unless the request came by letter", context do
      erase!(context)
      assert %{success: 1} = Oban.drain_queue(queue: :default)
      assert_email_sent(subject: "Wattle Creek erased your data")

      {other_member, other} = member!(context.organisation, :member, context.administrator)
      send_invitations()

      erase!(
        %{context | member: other_member, user: other},
        %{},
        request!(%{context | member: other_member}, %{how_received: :letter})
      )

      assert %{success: 0} = Oban.drain_queue(queue: :default)
    end

    test "deletes the comments of the person, unless the erasure keeps them", context do
      soon = DateTime.add(DateTime.utc_now(), 1, :hour) |> DateTime.truncate(:second)
      task = Tasks.plan_task!(%{title: "Hay", due_at: soon}, context.admin)

      {:ok, gone} =
        Rescord.Comments.write({:task, task.id}, %{body: "I took the hay."}, context.options)

      {other_member, other} = member!(context.organisation, :member, context.administrator)
      other_options = [actor: other, tenant: context.organisation]
      {:ok, kept} = Rescord.Comments.write({:task, task.id}, %{body: "Me too."}, other_options)

      erase!(context)

      erase!(
        %{context | member: other_member, user: other},
        %{keep_comments: true},
        request!(%{context | member: other_member})
      )

      assert {:ok, nil} = Rescord.Comments.comment(gone.id, context.admin)
      assert {:ok, %{}} = Rescord.Comments.comment(kept.id, context.admin)

      people = Rescord.Comments.people([kept], context.admin)
      assert RescordWeb.CommentWords.person(people, other.id) == "Former member 2"
    end

    test "writes a marker in the store, with no email", context do
      erase!(context)

      key = Privacy.marker_key(context.organisation.id, context.member.id)
      assert {:ok, bytes} = Storage.get(key)
      refute bytes =~ to_string(context.user.email)
      assert [{^key, "marker of an erasure", _id}] = Privacy.file_keys(context.organisation.id)
    end

    test "is refused for a member who can change the members, except to a root user", context do
      {admin_member, other_admin} = member!(context.organisation, :administrator, context.root)
      request = request!(%{context | member: admin_member})

      assert {:error, :forbidden} = Privacy.erase(request, %{}, context.admin)

      assert {:ok, _done} =
               Privacy.erase(request, %{}, actor: context.root, tenant: context.organisation)

      assert Accounts.labels(context.admin)[other_admin.id] =~ "Former member"
    end

    test "is refused for a request that is closed", context do
      done = erase!(context)
      assert {:error, :closed} = Privacy.erase(done, %{}, context.admin)
    end
  end

  describe "a restore of an older dump" do
    test "erases the person again from the marker", context do
      email = to_string(context.user.email)
      erase!(context)
      schema = "org_#{context.organisation.id}"

      # The rows as an old dump has them.
      Repo.query!(
        "UPDATE \"#{schema}\".members SET erased_at = NULL, former_number = NULL, archived_at = NULL WHERE id = $1",
        [Ecto.UUID.dump!(context.member.id)]
      )

      Repo.query!("UPDATE users SET email = $1, erased_at = NULL WHERE id = $2", [
        email,
        Ecto.UUID.dump!(context.user.id)
      ])

      assert {:ok, 1} = Privacy.reapply_erasures()

      member = erased_member(context)
      assert member.former_number == 1
      assert is_nil(user(context).email)
      assert {:ok, 0} = Privacy.reapply_erasures()
    end
  end
end
