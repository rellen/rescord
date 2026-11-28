defmodule Rescord.CommentsTest do
  @moduledoc """
  Holds the comments of an organisation (issue 29, ADR 0106): who writes
  one and on what, who reads it, who is told and who follows, who changes
  and deletes one, the history that keeps no word, and a member who left.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use Rescord.DataCase, async: false

  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Comments, Expenses}
  alias Rescord.Comments.Comment

  setup do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {sam_member, sam} = member!(organisation, :member, administrator)
    {_, kim} = member!(organisation, :member, administrator)
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]

    visitor_role = Accounts.define_role!(%{name: "Visitor", powers: []}, admin)
    {visitor_member, visitor} = member!(organisation, :member, administrator)
    Accounts.set_member_role!(visitor_member, visitor_role.id, admin)

    {:ok,
     organisation: organisation,
     administrator: administrator,
     sam: sam,
     sam_member: sam_member,
     kim: kim,
     visitor: visitor,
     stranger: user!(),
     lists: lists,
     admin: admin,
     hazel: resident!(lists, admin, %{name: "Hazel"})}
  end

  defp as(context, user), do: [actor: user, tenant: context.organisation]

  defp role_of(context, user) do
    {:ok, member} = Accounts.member_of_user(user.id, [load: [:role]] ++ context.admin)
    Accounts.role_in(user, member)
  end

  defp write(context, user, fields, subject \\ nil) do
    Comments.write(subject || {:resident, context.hazel.id}, fields, as(context, user))
  end

  defp expense!(context, user) do
    Expenses.submit_expense!(
      %{
        paid_by: :member,
        amount: "40.00",
        incurred_on: Accounts.today(context.organisation),
        payee: "Northside Vet Clinic",
        description: "Worming tablets",
        category_id: context.lists.expense_category.veterinary
      },
      as(context, user)
    )
  end

  describe "a comment" do
    test "is on one record, by the writer, and each member reads it", context do
      assert {:ok, comment} = write(context, context.sam, %{body: "She ate **all** of it."})
      assert comment.author_id == context.sam.id
      assert comment.resident_id == context.hazel.id

      for user <- [context.kim, context.administrator, context.visitor] do
        assert {:ok, [%Comment{body: "She ate **all** of it."}]} =
                 Comments.comments_on({:resident, context.hazel.id}, as(context, user))
      end
    end

    test "needs words, at most 4,000 characters", context do
      assert {:error, %Ash.Error.Invalid{}} = write(context, context.sam, %{body: nil})
      assert {:error, %Ash.Error.Invalid{}} = write(context, context.sam, %{body: "   "})

      assert {:error, %Ash.Error.Invalid{}} =
               write(context, context.sam, %{body: String.duplicate("a", 4_001)})
    end

    test "names exactly one record", context do
      fields = %{
        body: "Two at once",
        resident_id: context.hazel.id,
        task_id: Ecto.UUID.generate()
      }

      assert {:error, %Ash.Error.Invalid{}} =
               Comments.write_comment(fields, as(context, context.sam))
    end

    test "is refused to a role without the power, and to a stranger", context do
      assert {:error, %Ash.Error.Forbidden{}} = write(context, context.visitor, %{body: "Hi"})
      assert {:error, %Ash.Error.Forbidden{}} = write(context, context.stranger, %{body: "Hi"})
      refute Comments.role_can?(:none, :write)
    end

    test "is refused on a record that the writer cannot read", context do
      expense = expense!(context, context.sam)

      # A member reads only their own expenses (ADR 0082).
      assert {:error, _error} =
               write(context, context.kim, %{body: "What is this?"}, {:expense, expense.id})

      assert {:error, _error} =
               write(context, context.sam, %{body: "Nobody"}, {:resident, Ecto.UUID.generate()})
    end
  end

  describe "a comment on an expense" do
    test "is read only by the people who read the expense", context do
      expense = expense!(context, context.sam)
      subject = {:expense, expense.id}

      assert {:ok, _} = write(context, context.administrator, %{body: "Approved."}, subject)
      assert {:ok, _} = write(context, context.sam, %{body: "Thanks."}, subject)

      assert {:ok, [_, _]} = Comments.comments_on(subject, as(context, context.sam))
      assert {:ok, [_, _]} = Comments.comments_on(subject, as(context, context.administrator))
      assert {:ok, []} = Comments.comments_on(subject, as(context, context.kim))
      assert {:ok, []} = Comments.comments_on(subject, as(context, context.visitor))
    end
  end

  describe "telling and following" do
    test "the writer and each person told follow the record", context do
      subject = {:resident, context.hazel.id}
      refute Comments.following?(subject, as(context, context.sam))

      assert {:ok, comment} =
               write(context, context.sam, %{body: "Can you look?", told_ids: [context.kim.id]})

      assert comment.told_ids == [context.kim.id]
      assert Comments.following?(subject, as(context, context.sam))
      assert Comments.following?(subject, as(context, context.kim))
      refute Comments.following?(subject, as(context, context.administrator))

      followers = Comments.followers_of(comment, tenant: context.organisation)
      assert Enum.sort(followers) == Enum.sort([context.sam.id, context.kim.id])
    end

    test "tells only members of the organisation", context do
      assert {:error, %Ash.Error.Invalid{}} =
               write(context, context.sam, %{body: "Hi", told_ids: [context.stranger.id]})

      assert {:error, %Ash.Error.Invalid{}} =
               write(context, context.sam, %{body: "Hi", told_ids: [Ecto.UUID.generate()]})
    end

    test "a person follows and stops, and twice is once", context do
      subject = {:resident, context.hazel.id}
      options = as(context, context.kim)

      assert {:ok, _} = Comments.follow(subject, options)
      assert {:ok, _} = Comments.follow(subject, options)
      assert Comments.following?(subject, options)

      assert :ok = Comments.unfollow(subject, options)
      refute Comments.following?(subject, options)
      assert :ok = Comments.unfollow(subject, options)
    end

    test "a person reads no follow of another", context do
      {:ok, _} = Comments.follow({:resident, context.hazel.id}, as(context, context.sam))
      refute Comments.following?({:resident, context.hazel.id}, as(context, context.kim))
    end
  end

  describe "a change and a delete" do
    test "the writer changes their own comment, and nobody else does", context do
      {:ok, comment} = write(context, context.sam, %{body: "Fed at 8."})

      assert {:error, %Ash.Error.Forbidden{}} =
               Comments.revise_comment(comment, "Fed at 9.", as(context, context.kim))

      assert {:error, %Ash.Error.Forbidden{}} =
               Comments.revise_comment(comment, "Fed at 9.", as(context, context.administrator))

      assert {:ok, revised} =
               Comments.revise_comment(comment, "Fed at 9.", as(context, context.sam))

      assert revised.body == "Fed at 9."
      assert revised.edited_at
    end

    test "the writer deletes their own, a moderator deletes any, a member no other", context do
      {:ok, one} = write(context, context.sam, %{body: "One"})
      {:ok, two} = write(context, context.sam, %{body: "Two"})

      assert {:error, %Ash.Error.Forbidden{}} =
               Comments.delete_comment(one, as(context, context.kim))

      assert :ok = Comments.delete_comment(one, as(context, context.sam))
      assert :ok = Comments.delete_comment(two, as(context, context.administrator))

      assert {:ok, []} = Comments.comments_on({:resident, context.hazel.id}, context.admin)
    end

    test "can?/4 says what the policy decides", context do
      {:ok, comment} = write(context, context.sam, %{body: "One"})
      member = role_of(context, context.sam)
      administrator = role_of(context, context.administrator)

      assert Comments.can?(member, context.sam, comment, :revise)
      assert Comments.can?(member, context.sam, comment, :delete)
      refute Comments.can?(member, context.kim, comment, :delete)
      refute Comments.can?(administrator, context.administrator, comment, :revise)
      assert Comments.can?(administrator, context.administrator, comment, :delete)
    end

    test "a moderator deletes each comment of one person", context do
      {:ok, _} = write(context, context.sam, %{body: "One"})
      {:ok, _} = write(context, context.sam, %{body: "Two"})
      {:ok, _} = write(context, context.kim, %{body: "Mine"})

      assert {:error, _} = Comments.erase(context.sam.id, as(context, context.kim))
      assert {:ok, 2} = Comments.erase(context.sam.id, context.admin)

      assert {:ok, [%Comment{body: "Mine"}]} =
               Comments.comments_on({:resident, context.hazel.id}, context.admin)
    end
  end

  describe "the history of a comment" do
    test "says who and when, and keeps no word of it", context do
      {:ok, comment} = write(context, context.sam, %{body: "The first words"})

      {:ok, comment} =
        Comments.revise_comment(comment, "The second words", as(context, context.sam))

      :ok = Comments.delete_comment(comment, as(context, context.sam))

      versions =
        Comment.Version
        |> Ash.read!(tenant: context.organisation, authorize?: false)
        |> Enum.filter(&(&1.version_source_id == comment.id))

      assert Enum.map(versions, & &1.version_action_name) |> Enum.sort() ==
               [:delete, :revise, :write]

      for version <- versions do
        text = inspect({version.changes, Map.get(version, :version_action_inputs)})
        refute text =~ "first words"
        refute text =~ "second words"
      end
    end
  end

  describe "a member who left" do
    test "keeps their name on their comments, marked as a former member", context do
      {:ok, comment} = write(context, context.sam, %{body: "I leave on Friday."})
      :ok = Accounts.remove_member(context.sam_member, context.admin)

      people = Comments.people([comment], context.admin)
      assert {email, :former} = people[context.sam.id]
      assert email == to_string(context.sam.email)
      assert {_, :member} = people[context.kim.id]

      assert RescordWeb.CommentWords.person(people, context.sam.id) ==
               "#{context.sam.email} (former member)"

      assert RescordWeb.CommentWords.person(%{}, context.sam.id) == "a former member"
    end
  end
end
