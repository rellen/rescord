defmodule RescordWeb.CommentPagesTest do
  @moduledoc """
  Holds the pages of the comments and the notifications (issue 29,
  ADR 0106): the comments of a resident, a task, an expense and a transfer
  copy, the bell of the site bar, the page of notifications, and the page
  of the settings of a root user.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Comments, Notifications, Tasks}

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

  describe "the comments of a resident" do
    test "a member writes one, with Markdown, and tells a member", context do
      {:ok, view, html} = live(context.conn, context.resident_path)
      assert html =~ "No comment yet."

      view
      |> form("#comments-comments form[data-comment]", %{
        "comment" => %{
          "body" => "**Weighed** her. <b>No</b> tags.",
          "told" => [context.kim.id]
        }
      })
      |> render_submit()

      html = render(view)

      assert has_element?(
               view,
               "#comments-comments ol[data-comments] li[data-own] strong",
               "Weighed"
             )

      assert html =~ "&lt;b&gt;No&lt;/b&gt; tags."
      assert html =~ "Told kim@example.org"
      assert has_element?(view, "#comments-comments p[data-follow]", "You get a notification")

      [comment] =
        Comments.comments_on({:resident, context.hazel.id}, as(context, context.sam)) |> elem(1)

      assert comment.told_ids == [context.kim.id]
    end

    test "the writer changes and deletes their own, and nobody else gets the buttons", context do
      {:ok, comment} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "Fed at 8."},
          as(context, context.kim)
        )

      {:ok, view, _html} = live(context.conn, context.resident_path)
      refute has_element?(view, "#comment-#{comment.id} footer button", "Delete")
      refute has_element?(view, "#change-comment-#{comment.id}")

      {:ok, view, _html} = live(context.kim_conn, context.resident_path)

      view
      |> form("#change-comment-#{comment.id}-form", %{"comment" => %{"body" => "Fed at 9."}})
      |> render_submit()

      assert has_element?(view, "#comment-#{comment.id}", "Fed at 9.")
      assert has_element?(view, "#comment-#{comment.id} header small", "changed")

      view |> element("#comment-#{comment.id} footer button", "Delete") |> render_click()
      refute has_element?(view, "#comment-#{comment.id}")
    end

    test "an event names only a comment that the page read", context do
      {:ok, comment} =
        Comments.write({:resident, context.hazel.id}, %{body: "Kim's"}, as(context, context.kim))

      {:ok, view, _html} = live(context.conn, context.resident_path)
      render_hook(view, "comments:delete", %{"widget" => "comments", "comment_id" => comment.id})
      render_hook(view, "comments:delete", %{"widget" => "nothing", "comment_id" => comment.id})
      render_hook(view, "comments:post", %{"widget" => "comments", "comment" => "not a map"})

      assert {:ok, [_]} = Comments.comments_on({:resident, context.hazel.id}, context.admin)
    end

    test "a member follows and stops", context do
      {:ok, view, _html} = live(context.conn, context.resident_path)

      view
      |> element("#comments-comments p[data-follow] button", "Get notifications")
      |> render_click()

      assert Comments.following?({:resident, context.hazel.id}, as(context, context.sam))

      view
      |> element("#comments-comments p[data-follow] button", "Stop notifications")
      |> render_click()

      refute Comments.following?({:resident, context.hazel.id}, as(context, context.sam))
    end

    test "shows what another person writes, at once", context do
      {:ok, view, _html} = live(context.conn, context.resident_path)

      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "From Kim"},
          as(context, context.kim)
        )

      assert render(view) =~ "From Kim"
    end

    test "names a member who left, as a former member", context do
      {:ok, _} =
        Comments.write({:resident, context.hazel.id}, %{body: "Bye"}, as(context, context.kim))

      {:ok, kim_member} = Rescord.Accounts.member_of_user(context.kim.id, context.admin)
      :ok = Rescord.Accounts.remove_member(kim_member, context.admin)

      {:ok, _view, html} = live(context.conn, context.resident_path)
      assert html =~ "kim@example.org (former member)"
      # A member who left is not offered to tell.
      refute html =~ ~s(value="#{context.kim.id}")
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
      {:ok, view, _html} = live(context.conn, journal)
      refute has_element?(view, "#comments-comments")

      assert has_element?(
               view,
               ~s(#entry-#{entry.id} a[href="#{journal}?entry=#{entry.id}"]),
               "Comments"
             )

      {:ok, view, _html} = live(context.conn, "#{journal}?entry=#{entry.id}")

      view
      |> form("#comments-comments form[data-comment]", %{
        "comment" => %{"body" => "Better today.", "told" => [context.kim.id]}
      })
      |> render_submit()

      assert has_element?(view, "#comments-comments li[data-own]", "Better today.")
      work!()

      {:ok, view, _html} = live(context.kim_conn, ~p"/o/#{context.short}/notifications")

      assert has_element?(
               view,
               ~s(ul[data-notifications] a[href^="#{journal}?entry=#{entry.id}"]),
               "An entry about Hazel"
             )
    end
  end

  describe "the page of a task" do
    test "shows the task and its comments, and the list links to it", context do
      task =
        Tasks.plan_task!(
          %{title: "Clean the barn pens", due_at: DateTime.add(DateTime.utc_now(), 1, :hour)},
          context.admin
        )

      {:ok, _} =
        Comments.write({:task, task.id}, %{body: "The hose leaks."}, as(context, context.kim))

      {:ok, _view, html} = live(context.conn, ~p"/o/#{context.short}/tasks/#{task.id}")
      assert html =~ "Clean the barn pens"
      assert html =~ "The hose leaks."

      {:ok, view, _html} = live(context.conn, ~p"/o/#{context.short}/tasks")
      html = render_async(view)
      assert html =~ ~s(href="/o/#{context.short}/tasks/#{task.id}")
    end

    test "sends a person to the tasks for a task that is not there", context do
      assert {:error, {:redirect, %{to: to}}} =
               live(context.conn, ~p"/o/#{context.short}/tasks/#{Ecto.UUID.generate()}")

      assert to == ~p"/o/#{context.short}/tasks"
      assert {:error, {:redirect, _}} = live(context.conn, ~p"/o/#{context.short}/tasks/nope")
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

      {:ok, view, _html} = live(context.conn, ~p"/o/#{context.short}")
      assert has_element?(view, "header a[data-inbox] data", "1")

      {:ok, view, html} = live(context.conn, ~p"/o/#{context.short}/notifications")
      assert html =~ "1 new"
      assert has_element?(view, "ul[data-notifications] li[data-new] a", "Hazel")
      assert has_element?(view, "ul[data-notifications] blockquote em", "look")
      assert html =~ "kim@example.org told you about a comment on a resident"

      view |> element("button", "Mark all as read") |> render_click()
      refute has_element?(view, "ul[data-notifications] li[data-new]")
      assert render(view) =~ "Nothing new"
    end

    test "the bell counts a new one on the page that is open", context do
      {:ok, view, _html} = live(context.conn, ~p"/o/#{context.short}")
      refute has_element?(view, "header a[data-inbox] data")

      {:ok, _} =
        Comments.write(
          {:resident, context.hazel.id},
          %{body: "Look", told_ids: [context.sam.id]},
          as(context, context.kim)
        )

      work!()
      assert has_element?(view, "header a[data-inbox] data", "1")
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
      {:ok, view, _html} = live(context.conn, context.resident_path)
      assert Notifications.unread_count(as(context, context.sam)) == 0
      refute has_element?(view, "header a[data-inbox] data")
    end

    test "has no channel but the page while the server has none on", context do
      {:ok, _view, html} = live(context.conn, ~p"/o/#{context.short}/notifications")
      refute html =~ "This device"
      refute html =~ "What goes where"
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

      {:ok, view, html} = live(context.conn, ~p"/o/#{context.short}/notifications")
      assert html =~ "This device"
      assert has_element?(view, "#push-device[phx-hook=Push][data-key]")

      view |> element("button", "Get notifications on ntfy") |> render_click()
      assert has_element?(view, "output[data-address]", "https://ntfy.example.org/")

      view
      |> form("#preferences-form", %{
        "preferences" => %{"told" => ["", "ntfy"], "comment" => [""]}
      })
      |> render_submit()

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

      {:ok, view, _html} = live(context.conn, ~p"/o/#{context.short}/notifications")
      key = Notifications.WebPush.encode(Notifications.WebPush.keys().public)
      auth = Notifications.WebPush.encode(:crypto.strong_rand_bytes(16))

      render_hook(view, "push-subscribe", %{
        "endpoint" => "https://evil.example.org/x",
        "keys" => %{"p256dh" => key, "auth" => auth},
        "device" => "iphone"
      })

      assert Notifications.devices(actor: context.sam) == []

      render_hook(view, "push-subscribe", %{
        "endpoint" => "https://web.push.apple.com/abc",
        "keys" => %{"p256dh" => key, "auth" => auth},
        "device" => "made-up"
      })

      assert [%{device: :other}] = Notifications.devices(actor: context.sam)
      assert has_element?(view, "ul[data-devices] li", "A device")

      render_hook(view, "push-unsubscribe", %{"endpoint" => "https://web.push.apple.com/abc"})
      assert Notifications.devices(actor: context.sam) == []
    end
  end

  describe "the settings of a root user" do
    test "make the keys, and save the channels", context do
      conn = sign_in(build_conn(), context.root)
      {:ok, view, html} = live(conn, ~p"/root/push")
      assert html =~ "Make the keys"

      view |> element("button", "Make the keys") |> render_click()
      assert has_element?(view, "dd code")

      view
      |> form("#push-settings", %{
        "settings" => %{"contact" => "mailto:ops@example.org", "push_on" => "true"}
      })
      |> render_submit()

      assert Notifications.settings(actor: context.root).push_on

      view |> form("#ntfy-token", %{"ntfy" => %{"token" => "tk_secret"}}) |> render_submit()
      html = render(view)
      assert html =~ "The server has a token"
      refute html =~ "tk_secret"
    end

    test "is not for a member", context do
      assert {:error, {:redirect, _}} = live(context.conn, ~p"/root/push")
    end
  end
end
