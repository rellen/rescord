defmodule RescordWeb.CommentPagesTest do
  @moduledoc """
  Holds the pages of the comments and the notifications (issue 29,
  ADR 0106): the comments of a resident, a task, an expense and a transfer
  copy, the bell of the site bar, the page of notifications, and the page
  of the settings of a root user. The tests find what a person finds
  (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_async: 1, render_hook: 3]
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Comments, Notifications, Tasks}

  setup %{conn: conn} do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root, "robin@example.org")
    {_, sam} = member!(organisation, :member, administrator, "sam@example.org")
    {_, kim} = member!(organisation, :member, administrator, "kim@example.org")
    lists = lists!(organisation, root)
    admin = [actor: administrator, tenant: organisation]
    hazel = resident!(lists, admin, %{name: "Hazel"})
    short = organisation.short_name

    {:ok,
     root: root,
     organisation: organisation,
     administrator: administrator,
     sam: sam,
     kim: kim,
     admin: admin,
     hazel: hazel,
     short: short,
     resident_path: ~p"/o/#{short}/residents/#{hazel.id}",
     conn: sign_in(conn, sam),
     kim_conn: sign_in(build_conn(), kim)}
  end

  defp as(context, user), do: [actor: user, tenant: context.organisation]
  defp work!, do: Oban.drain_queue(queue: :default, with_recursion: true, with_safety: false)

  defp comments, do: main() |> region("Comments")
  defp comment(words), do: comments() |> item(words)
  defp bell(words), do: navigation("Site") |> link(words)
  defp newest, do: main() |> region("The newest")

  describe "the comments of a resident" do
    test "a member writes one, with Markdown, and tells a member", context do
      session =
        context.conn
        |> visit(context.resident_path)
        |> assert_has(comments(), text: "No comment yet.")
        |> within(comments(), fn part ->
          part
          |> fill_in("Write a comment", with: "**Weighed** her. <b>No</b> tags.")
          |> check("kim@example.org")
          |> click(button("Write the comment"))
        end)
        |> assert_has(comment(~r/Weighed/), text: "Weighed her. <b>No</b> tags.")
        |> assert_has(comment(~r/Weighed/), text: "Told kim@example.org")
        |> assert_has(comments(), text: "You get a notification for each new comment here.")

      # The words are Markdown, and a tag of HTML is words.
      within(session, comment(~r/Weighed/), &assert_has(&1, "strong", text: "Weighed"))
      within(session, comment(~r/Weighed/), &refute_has(&1, "b"))

      [comment] =
        Comments.comments_on({:resident, context.hazel.id}, as(context, context.sam)) |> elem(1)

      assert comment.told_ids == [context.kim.id]
    end

    test "the writer changes and deletes their own, and nobody else gets the buttons", context do
      {:ok, _comment} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "Fed at 8."},
          as(context, context.kim)
        )

      context.conn
      |> visit(context.resident_path)
      |> assert_has(comment(~r/Fed at 8\./))
      |> refute_has(comment(~r/Fed at 8\./) |> details("Delete"))
      |> refute_has(comment(~r/Fed at 8\./) |> details("Change"))

      context.kim_conn
      |> visit(context.resident_path)
      |> within(comment(~r/Fed at 8\./) |> details("Change"), fn change ->
        change
        |> fill_in("The comment", with: "Fed at 9.")
        |> click(button("Save the comment"))
      end)
      |> assert_has(comment(~r/Fed at 9\./), text: "changed")
      |> click(comment(~r/Fed at 9\./) |> details("Delete") |> button("Delete the comment"))
      |> refute_has(comment(~r/Fed at/))
    end

    test "an event names only a comment that the page read", context do
      {:ok, comment} =
        Comments.write({:resident, context.hazel.id}, %{body: "Kim's"}, as(context, context.kim))

      context.conn
      |> visit(context.resident_path)
      |> unwrap(
        &render_hook(&1, "comments:delete", %{"widget" => "comments", "comment_id" => comment.id})
      )
      |> unwrap(
        &render_hook(&1, "comments:delete", %{"widget" => "nothing", "comment_id" => comment.id})
      )
      |> unwrap(
        &render_hook(&1, "comments:post", %{"widget" => "comments", "comment" => "not a map"})
      )
      |> assert_has(comment(~r/Kim's/))

      assert {:ok, [_]} = Comments.comments_on({:resident, context.hazel.id}, context.admin)
    end

    test "a member follows and stops", context do
      session =
        context.conn
        |> visit(context.resident_path)
        |> click(comments() |> button("Get notifications for this"))

      assert Comments.following?({:resident, context.hazel.id}, as(context, context.sam))

      session
      |> click(comments() |> button("Stop notifications for this"))
      |> assert_has(comments() |> button("Get notifications for this"))

      refute Comments.following?({:resident, context.hazel.id}, as(context, context.sam))
    end

    test "shows what another person writes, at once", context do
      session = visit(context.conn, context.resident_path)

      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "From Kim"},
          as(context, context.kim)
        )

      assert_has(session, comment(~r/From Kim/), text: "kim@example.org")
    end

    test "names a member who left, as a former member", context do
      {:ok, _} =
        Comments.write({:resident, context.hazel.id}, %{body: "Bye"}, as(context, context.kim))

      {:ok, kim_member} = Rescord.Accounts.member_of_user(context.kim.id, context.admin)
      :ok = Rescord.Accounts.remove_member(kim_member, context.admin)

      context.conn
      |> visit(context.resident_path)
      |> assert_has(comment(~r/Bye/), text: "kim@example.org (former member)")
      # A member who left is not offered to tell.
      |> refute_has(comments() |> details("Tell someone") |> field("kim@example.org"))
      |> assert_has(comments() |> details("Tell someone") |> field("robin@example.org"))
    end
  end

  describe "the comments of a journal entry" do
    test "show on the page of the entry, and its notification links there", context do
      entry =
        Rescord.Journal.write_entry!(
          %{resident_id: context.hazel.id, kind: :general, note: "Limping a little"},
          context.admin
        )

      journal = ~p"/o/#{context.short}/residents/#{context.hazel.id}/journal"

      session =
        context.conn
        |> visit(journal)
        |> unwrap(&render_async/1)
        |> refute_has(comments())

      assert href(session, main() |> link(~r/^Comments/)) == "#{journal}?entry=#{entry.id}"

      session
      |> click(main() |> link(~r/^Comments/))
      |> unwrap(&render_async/1)
      |> within(comments(), fn part ->
        part
        |> fill_in("Write a comment", with: "Better today.")
        |> check("kim@example.org")
        |> click(button("Write the comment"))
      end)
      |> assert_has(comment(~r/Better today\./))

      work!()

      session =
        context.kim_conn
        |> visit(~p"/o/#{context.short}/notifications")
        |> assert_has(newest() |> link("An entry about Hazel"))

      assert href(session, newest() |> link("An entry about Hazel")) =~
               "#{journal}?entry=#{entry.id}"
    end
  end

  describe "the page of a task" do
    test "shows the task and its comments, and the list links to it", context do
      # Noon of today in the organisation, since the list shows the tasks of
      # the day there. An hour from now fell on the next day there in the
      # last hour before its midnight.
      organisation = context.organisation
      due_at = Accounts.local_instant(organisation, Accounts.today(organisation), ~T[12:00:00])

      task = Tasks.plan_task!(%{title: "Clean the barn pens", due_at: due_at}, context.admin)

      {:ok, _} =
        Comments.write({:task, task.id}, %{body: "The hose leaks."}, as(context, context.kim))

      context.conn
      |> visit(~p"/o/#{context.short}/tasks/#{task.id}")
      |> assert_has(main() |> heading(level: 1), text: "Clean the barn pens")
      |> assert_has(comment(~r/The hose leaks\./))

      day = Rescord.Accounts.local_date(context.organisation, task.due_at)

      session =
        context.conn
        |> visit(~p"/o/#{context.short}/tasks?#{[day: Date.to_iso8601(day)]}")
        |> unwrap(&render_async/1)

      assert href(session, main() |> link("Clean the barn pens")) ==
               "/o/#{context.short}/tasks/#{task.id}"
    end

    test "sends a person to the tasks for a task that is not there", context do
      for id <- [Ecto.UUID.generate(), "nope"] do
        context.conn
        |> visit(~p"/o/#{context.short}/tasks/#{id}")
        |> assert_path(~p"/o/#{context.short}/tasks")
      end
    end
  end

  describe "the notifications" do
    test "the bell counts the new ones, and the page lists them with their record", context do
      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "Can you *look*?", told_ids: [context.sam.id]},
          as(context, context.kim)
        )

      work!()

      context.conn
      |> visit(~p"/o/#{context.short}")
      |> assert_has(bell("Notifications 1 new"))

      session =
        context.conn
        |> visit(~p"/o/#{context.short}/notifications")
        |> assert_has(main(), text: "1 new")
        |> assert_has(newest() |> item(~r/^Hazel/), state: "info", text: "New")
        |> assert_has(newest() |> item(~r/^Hazel/),
          text: "kim@example.org told you about a comment on a resident"
        )

      within(
        session,
        newest() |> item(~r/^Hazel/),
        &assert_has(&1, "blockquote em", text: "look")
      )

      session
      |> click(button("Mark all as read"))
      |> refute_has(newest() |> item(~r/^Hazel/), state: "info")
      |> assert_has(main(), text: "Nothing new")
    end

    test "the bell counts a new one on the page that is open", context do
      session =
        context.conn
        |> visit(~p"/o/#{context.short}")
        |> assert_has(bell("Notifications"))

      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "Look", told_ids: [context.sam.id]},
          as(context, context.kim)
        )

      work!()
      assert_has(session, bell("Notifications 1 new"))
    end

    test "opening the record marks its notifications as read", context do
      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "Look", told_ids: [context.sam.id]},
          as(context, context.kim)
        )

      work!()
      assert Notifications.unread_count(as(context, context.sam)) == 1
      session = visit(context.conn, context.resident_path)
      assert Notifications.unread_count(as(context, context.sam)) == 0
      assert_has(session, bell("Notifications"))
    end

    test "has no channel but the page while the server has none on", context do
      context.conn
      |> visit(~p"/o/#{context.short}/notifications")
      |> assert_has(newest())
      |> refute_has(main() |> region("This device"))
      |> refute_has(main() |> region("What goes where"))
    end

    test "turns ntfy on, shows the address, and saves the choices", context do
      {:ok, _} = Notifications.make_keys(actor: context.root)

      {:ok, _} =
        Notifications.save_settings(
          %{
            contact: "mailto:ops@example.org",
            push_on: true,
            ntfy_url: "https://ntfy.example.org",
            ntfy_on: true
          },
          actor: context.root
        )

      where = main() |> region("What goes where")

      session =
        context.conn
        |> visit(~p"/o/#{context.short}/notifications")
        |> assert_has(main() |> region("This device"))
        |> click(button("Get notifications on ntfy"))
        |> assert_has(main() |> region("ntfy") |> status(), text: "https://ntfy.example.org/")

      # The page is where the hook of the browser asks for a device.
      assert attribute(session, main() |> region("This device") |> article(nil), "phx-hook") ==
               "Push"

      session
      # Each kind has the same boxes, so a box is found in its group: the
      # group has an id, since PhoenixTest finds the form of a box inside the
      # part that `within/3` gives.
      |> within(where, fn part ->
        part
        |> uncheck("#preferences-told input", "On my devices")
        |> uncheck("#preferences-comment input", "On my devices")
        |> uncheck("#preferences-comment input", "On ntfy")
        |> click(button("Save"))
      end)

      assert Notifications.preferences(as(context, context.sam)) == %{
               told: [:ntfy],
               comment: []
             }
    end

    test "takes a device from the hook, and refuses another address", context do
      {:ok, _} = Notifications.make_keys(actor: context.root)

      {:ok, _} =
        Notifications.save_settings(%{contact: "mailto:ops@example.org", push_on: true},
          actor: context.root
        )

      key = Notifications.WebPush.encode(Notifications.WebPush.keys().public)
      auth = Notifications.WebPush.encode(:crypto.strong_rand_bytes(16))
      session = visit(context.conn, ~p"/o/#{context.short}/notifications")

      # The hook of the page sends what the browser gave it.
      unwrap(
        session,
        &render_hook(&1, "push-subscribe", %{
          "endpoint" => "https://evil.example.org/x",
          "keys" => %{"p256dh" => key, "auth" => auth},
          "device" => "iphone"
        })
      )

      assert Notifications.devices(actor: context.sam) == []

      session
      |> unwrap(
        &render_hook(&1, "push-subscribe", %{
          "endpoint" => "https://web.push.apple.com/abc",
          "keys" => %{"p256dh" => key, "auth" => auth},
          "device" => "made-up"
        })
      )
      |> assert_has(main() |> region("Your devices") |> item(~r/^A device\b/))
      |> unwrap(
        &render_hook(&1, "push-unsubscribe", %{"endpoint" => "https://web.push.apple.com/abc"})
      )

      assert [] == Notifications.devices(actor: context.sam)
    end
  end

  describe "the settings of a root user" do
    test "make the keys, and save the channels", context do
      session =
        build_conn()
        |> sign_in(context.root)
        |> visit(~p"/root/push")
        |> click(button("Make the keys"))

      assert text(session, main() |> definition("Public key")) =~ ", made on "

      session
      |> fill_in("Contact for the push services", with: "mailto:ops@example.org")
      |> check("Send notifications to devices")
      |> click(button("Save"))

      assert Notifications.settings(actor: context.root).push_on

      session =
        session
        |> fill_in("The token", with: "tk_secret")
        |> click(button("Save the token"))
        |> assert_has(main(), text: "The server has a token")
        |> refute_has("*", text: "tk_secret")

      refute session |> PhoenixTest.Driver.render_html() |> LazyHTML.to_html() =~ "tk_secret"
    end

    test "is not for a member", context do
      context.conn |> visit(~p"/root/push") |> assert_path("/")
    end
  end
end
