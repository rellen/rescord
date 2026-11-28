defmodule RescordWeb.CalendarPagesTest do
  @moduledoc """
  Holds the page of the calendar feeds (ADR 0074): a member makes a feed
  and reads its address one time, revokes a feed, and reads why their role
  can make none; a person with the power `members` sees and revokes the
  feeds of the other members; and the pages that lead here.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures

  alias Rescord.{Accounts, Calendars, Tasks}

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
     page: ~p"/o/#{organisation.short_name}/calendar",
     admin: [actor: administrator, tenant: organisation],
     options: [actor: user, tenant: organisation]}
  end

  # The path of the address of a feed that the page shows, with its query.
  defp address(view) do
    [address] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("input#feed-address")
      |> LazyHTML.attribute("value")

    address
  end

  defp path_of(address) do
    uri = URI.parse(address)
    "#{uri.path}?#{uri.query}"
  end

  describe "a member" do
    test "makes a feed, and reads its address one time", context do
      {:ok, due_at} =
        Accounts.local_instant(
          context.organisation,
          "#{Date.to_iso8601(Accounts.today(context.organisation))}T23:30"
        )

      Tasks.plan_task!(%{title: "Evening feed", due_at: due_at}, context.admin)

      conn = sign_in(build_conn(), context.user)
      {:ok, view, _html} = live(conn, context.page)

      assert has_element?(view, "h1", "Calendar feeds")
      assert has_element?(view, "#no-feeds", "You have no feed")
      refute has_element?(view, "#new-address")
      refute has_element?(view, "#other-feeds-heading")

      # The form starts with the name of the organisation, and with no note.
      assert has_element?(view, ~s(form#new-feed input[name="feed[name]"][value="Wattle Creek"]))

      assert has_element?(
               view,
               ~s(form#new-feed select[name="feed[tasks]"] option[selected][value="mine"])
             )

      refute has_element?(view, ~s(form#new-feed input[name="feed[with_notes]"][checked]))

      view
      |> form("#new-feed", %{
        "feed" => %{"name" => "My phone", "tasks" => "all", "with_expiry" => "true"}
      })
      |> render_submit()

      assert has_element?(view, "#new-address h2", "The address of My phone")
      assert has_element?(view, "#new-address [role=status]", "this one time")

      assert has_element?(
               view,
               ~s(#new-address button[data-copy="feed-address"]),
               "Copy the address"
             )

      assert has_element?(view, "input#feed-address[readonly]")

      address = address(view)

      assert String.starts_with?(
               address,
               "#{RescordWeb.Endpoint.url()}/o/#{context.organisation.short_name}/calendar.ics?token="
             )

      # The address reads the feed, with no session.
      assert response(get(build_conn(), path_of(address)), 200) =~ "SUMMARY:Evening feed"

      # The feed is in the list, with its parts, and the form is new again.
      assert {:ok, [feed]} = Calendars.feeds_of(context.user, context.options)
      assert %{name: "My phone", tasks: :all, with_expiry: true, with_notes: false} = feed
      assert has_element?(view, "#feed-#{feed.id} strong", "My phone")
      assert has_element?(view, "#feed-#{feed.id}", "Each task. The expiry dates of the stock.")
      assert has_element?(view, ~s(form#new-feed input[name="feed[name]"][value="Wattle Creek"]))

      # The page that opens again has the feed, and no address.
      {:ok, view, _html} = live(conn, context.page)
      assert has_element?(view, "#feed-#{feed.id}", "Last read on")
      refute has_element?(view, "#new-address")
      refute render(view) =~ "token="
    end

    test "reads what is wrong with a feed that Rescord refuses", context do
      conn = sign_in(build_conn(), context.user)
      {:ok, view, _html} = live(conn, context.page)

      html =
        view
        |> form("#new-feed", %{"feed" => %{"name" => "Nothing", "tasks" => "none"}})
        |> render_submit()

      assert html =~ "the feed would be empty"
      assert has_element?(view, "#new-feed-heading ~ [role=alert]")
      refute has_element?(view, "#new-address")
      # The form keeps what the person typed.
      assert has_element?(view, ~s(form#new-feed input[name="feed[name]"][value="Nothing"]))
      assert {:ok, []} = Calendars.feeds_of(context.user, context.options)

      # A forged choice of tasks makes no feed, and no atom.
      render_submit(view, "subscribe", %{"feed" => %{"name" => "Forged", "tasks" => "everything"}})

      assert has_element?(view, "[role=alert]", "Choose which tasks the feed holds")
      render_submit(view, "subscribe", %{"feed" => "not a form"})
      assert {:ok, []} = Calendars.feeds_of(context.user, context.options)
    end

    test "revokes a feed, and its address reads nothing more", context do
      conn = sign_in(build_conn(), context.user)
      {:ok, view, _html} = live(conn, context.page)

      view
      |> form("#new-feed", %{"feed" => %{"name" => "My phone", "tasks" => "all"}})
      |> render_submit()

      address = address(view)
      assert {:ok, [feed]} = Calendars.feeds_of(context.user, context.options)

      # Revoking asks first: a confirm step with the name of the feed.
      assert has_element?(
               view,
               ~s(#feed-#{feed.id} details[data-confirm-step] summary[aria-label="Revoke the feed My phone"])
             )

      assert has_element?(
               view,
               ~s(#feed-#{feed.id} button[data-variant="danger"]),
               "Revoke the feed My phone"
             )

      html = view |> element("#feed-#{feed.id} button") |> render_click()

      assert html =~ "The feed My phone is revoked."
      assert has_element?(view, "#no-feeds")
      # The address of the revoked feed goes from the page.
      refute has_element?(view, "#new-address")
      assert response(get(build_conn(), path_of(address)), 404)

      # A forged id revokes nothing.
      render_click(view, "revoke", %{"id" => Ash.UUID.generate()})
      render_click(view, "revoke", %{"id" => %{"a" => "map"}})
    end

    test "whose role has no power calendar reads why, and makes no feed", context do
      {:ok, role} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {:ok, _member} = Accounts.set_member_role(context.member, role.id, context.admin)

      conn = sign_in(build_conn(), context.user)
      {:ok, view, _html} = live(conn, context.page)

      assert has_element?(view, "#no-calendar", "Your role cannot make a calendar feed")
      refute has_element?(view, "form#new-feed")

      render_submit(view, "subscribe", %{"feed" => %{"name" => "Forged", "tasks" => "all"}})

      assert Ash.read!(Rescord.Calendars.Feed, tenant: context.organisation, authorize?: false) ==
               []
    end
  end

  describe "a person with the power members" do
    test "sees the feeds of the other members, and revokes one", context do
      feed = Calendars.subscribe!(%{name: "My phone", tasks: :all}, context.options)
      token = Calendars.token(feed)
      own = Calendars.subscribe!(%{name: "The office"}, context.admin)

      conn = sign_in(build_conn(), context.administrator)
      {:ok, view, html} = live(conn, context.page)

      assert has_element?(view, "#own-feeds #feed-#{own.id}", "The office")
      assert has_element?(view, "#other-feeds #feed-#{feed.id} strong", "My phone")
      assert has_element?(view, "#other-feeds #feed-#{feed.id}", to_string(context.user.email))
      assert has_element?(view, "#other-feeds #feed-#{feed.id}", "No calendar app read it yet")
      # The page of another person holds no address of the feed.
      refute html =~ token
      refute html =~ "token="

      label = "Revoke the feed My phone of #{context.user.email}"
      view |> element(~s(#feed-#{feed.id} button[data-variant="danger"]), label) |> render_click()

      assert has_element?(view, "#no-other-feeds", "No other member has a feed")
      assert has_element?(view, "#own-feeds #feed-#{own.id}")
      assert Calendars.fetch(context.organisation.short_name, token) == :error
    end

    test "is not a plain member: a member sees no feed of another person", context do
      Calendars.subscribe!(%{name: "The office"}, context.admin)

      conn = sign_in(build_conn(), context.user)
      {:ok, view, html} = live(conn, context.page)

      refute has_element?(view, "#other-feeds-heading")
      refute html =~ "The office"
    end
  end

  describe "a root user who is not a member" do
    test "has no feed, and sees the feeds of the members", context do
      feed = Calendars.subscribe!(%{name: "My phone", tasks: :all}, context.options)

      conn = sign_in(build_conn(), context.root)
      {:ok, view, _html} = live(conn, context.page)

      assert has_element?(view, "#not-a-member", "You are not a member of Wattle Creek")
      refute has_element?(view, "form#new-feed")
      refute has_element?(view, "#own-feeds-heading")
      assert has_element?(view, "#other-feeds #feed-#{feed.id}", "My phone")
    end
  end

  describe "the page" do
    test "says how to subscribe, and that a calendar changes nothing", context do
      conn = sign_in(build_conn(), context.user)
      {:ok, view, _html} = live(conn, context.page)

      assert has_element?(view, "#how-to-heading", "How to subscribe")
      assert has_element?(view, "section", "changes nothing in Rescord")
    end

    test "is one link from the first page and from the tasks", context do
      conn = sign_in(build_conn(), context.user)
      short = context.organisation.short_name

      {:ok, view, _html} = live(conn, ~p"/o/#{short}")
      assert has_element?(view, ~s(nav ul[data-links] a[href="/o/#{short}/calendar"]))

      {:ok, view, _html} = live(conn, ~p"/o/#{short}/tasks")
      assert has_element?(view, ~s(header a[href="/o/#{short}/calendar"]), "Calendar feeds")
    end

    test "sends away a person who is not signed in", context do
      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), context.page)
    end
  end
end
