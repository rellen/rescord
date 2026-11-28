defmodule RescordWeb.CalendarPagesTest do
  @moduledoc """
  Holds the page of the calendar feeds (ADR 0074): a member makes a feed
  and reads its address one time, revokes a feed, and reads why their role
  can make none; a person with the power `members` sees and revokes the
  feeds of the other members; and the pages that lead here. The tests find
  what a person finds (ADR 0107).

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_submit: 3, render_click: 3]
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

  defp own, do: main() |> region("Your feeds")
  defp others, do: main() |> region("The feeds of the other members")
  defp make, do: main() |> region("Make a feed")
  defp feed(scope, %Regex{} = name), do: scope |> item(name)
  defp feed(scope, name), do: scope |> item(~r/^#{name}\b/)

  @name "Name, as your calendar app shows it"

  # The whole page, with its attributes: no address of a feed is in any.
  defp html(session), do: session |> PhoenixTest.Driver.render_html() |> LazyHTML.to_html()

  # The path of an address of a feed, with its query.
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

      session =
        conn
        |> visit(context.page)
        |> assert_has(main() |> heading(level: 1), text: "Calendar feeds")
        |> assert_has(own(), text: "You have no feed")
        |> refute_has(main() |> region("The address of My phone"))
        |> refute_has(others())

      # The form starts with the name of the organisation, and with no note.
      assert value(session, make() |> field(@name)) == "Wattle Creek"
      assert value(session, make() |> field("Tasks")) == "The tasks that name me"
      refute checked?(session, make() |> field("Include the notes that people wrote"))

      session =
        session
        |> fill_in(@name, with: "My phone")
        |> select("Tasks", option: "Each task")
        |> check("The expiry dates of the stock")
        |> click(button("Make the feed"))

      shown = main() |> region("The address of My phone")

      session
      |> assert_has(shown |> status(), text: "this one time")
      |> assert_has(shown |> button("Copy the address"))
      |> assert_has("#feed-address[readonly]")

      address = value(session, shown |> field("Address of the calendar"))

      assert String.starts_with?(
               address,
               "#{RescordWeb.Endpoint.url()}/o/#{context.organisation.short_name}/calendar.ics?token="
             )

      # The address reads the feed, with no session.
      assert response(get(build_conn(), path_of(address)), 200) =~ "SUMMARY:Evening feed"

      # The feed is in the list, with its parts, and the form is new again.
      assert {:ok, [feed]} = Calendars.feeds_of(context.user, context.options)
      assert %{name: "My phone", tasks: :all, with_expiry: true, with_notes: false} = feed

      assert_has(session, feed(own(), "My phone"),
        text: "Each task. The expiry dates of the stock."
      )

      assert value(session, make() |> field(@name)) == "Wattle Creek"

      # The page that opens again has the feed, and no address.
      session =
        conn
        |> visit(context.page)
        |> assert_has(feed(own(), "My phone"), text: "Last read on")
        |> refute_has(shown)

      refute html(session) =~ "token="
    end

    test "reads what is wrong with a feed that Rescord refuses", context do
      session =
        build_conn()
        |> sign_in(context.user)
        |> visit(context.page)
        |> fill_in(@name, with: "Nothing")
        |> select("Tasks", option: "No tasks")
        |> click(button("Make the feed"))
        |> assert_has(make() |> alert(), text: "the feed would be empty")
        |> refute_has(main() |> region("The address of Nothing"))

      # The form keeps what the person typed.
      assert value(session, make() |> field(@name)) == "Nothing"
      assert {:ok, []} = Calendars.feeds_of(context.user, context.options)

      # A forged choice of tasks makes no feed, and no atom.
      session
      |> unwrap(
        &render_submit(&1, "subscribe", %{
          "feed" => %{"name" => "Forged", "tasks" => "everything"}
        })
      )
      |> assert_has(make() |> alert(), text: "Choose which tasks the feed holds")
      |> unwrap(&render_submit(&1, "subscribe", %{"feed" => "not a form"}))

      assert {:ok, []} = Calendars.feeds_of(context.user, context.options)
    end

    test "revokes a feed, and its address reads nothing more", context do
      session =
        build_conn()
        |> sign_in(context.user)
        |> visit(context.page)
        |> fill_in(@name, with: "My phone")
        |> select("Tasks", option: "Each task")
        |> click(button("Make the feed"))

      address = value(session, field("Address of the calendar"))
      # Revoking asks first: a confirm step with the name of the feed.
      step = feed(own(), "My phone") |> details("Revoke the feed My phone")
      refute open?(session, step)

      session
      |> click(step |> button("Revoke the feed My phone"))
      |> assert_has(status(), text: "The feed My phone is revoked.")
      |> assert_has(own(), text: "You have no feed")
      # The address of the revoked feed goes from the page.
      |> refute_has(main() |> region("The address of My phone"))
      # A forged id revokes nothing.
      |> unwrap(&render_click(&1, "revoke", %{"id" => Ash.UUID.generate()}))
      |> unwrap(&render_click(&1, "revoke", %{"id" => %{"a" => "map"}}))
      |> assert_has(main() |> heading(level: 1), text: "Calendar feeds")

      assert response(get(build_conn(), path_of(address)), 404)
    end

    test "whose role has no power calendar reads why, and makes no feed", context do
      {:ok, role} = Accounts.define_role(%{name: "Feeder", powers: [:tasks]}, context.admin)
      {:ok, _member} = Accounts.set_member_role(context.member, role.id, context.admin)

      build_conn()
      |> sign_in(context.user)
      |> visit(context.page)
      |> assert_has(main(), text: "Your role cannot make a calendar feed")
      |> refute_has(make())
      |> unwrap(
        &render_submit(&1, "subscribe", %{"feed" => %{"name" => "Forged", "tasks" => "all"}})
      )

      assert Ash.read!(Rescord.Calendars.Feed, tenant: context.organisation, authorize?: false) ==
               []
    end
  end

  describe "a person with the power members" do
    test "sees the feeds of the other members, and revokes one", context do
      feed = Calendars.subscribe!(%{name: "My phone", tasks: :all}, context.options)
      token = Calendars.token(feed)
      Calendars.subscribe!(%{name: "The office"}, context.admin)
      email = to_string(context.user.email)

      session =
        build_conn()
        |> sign_in(context.administrator)
        |> visit(context.page)
        |> assert_has(feed(own(), "The office"))
        |> assert_has(feed(others(), ~r/^My phone #{Regex.escape(email)} /))
        |> assert_has(feed(others(), "My phone"), text: "No calendar app read it yet")

      # The page of another person holds no address of the feed.
      refute html(session) =~ token
      refute html(session) =~ "token="

      session
      |> click(feed(others(), "My phone") |> button("Revoke the feed My phone of #{email}"))
      |> assert_has(others(), text: "No other member has a feed")
      |> assert_has(feed(own(), "The office"))

      assert Calendars.fetch(context.organisation.short_name, token) == :error
    end

    test "is not a plain member: a member sees no feed of another person", context do
      Calendars.subscribe!(%{name: "The office"}, context.admin)

      build_conn()
      |> sign_in(context.user)
      |> visit(context.page)
      |> refute_has(others())
      |> refute_has("*", text: "The office")
    end
  end

  describe "a root user who is not a member" do
    test "has no feed, and sees the feeds of the members", context do
      Calendars.subscribe!(%{name: "My phone", tasks: :all}, context.options)

      build_conn()
      |> sign_in(context.root)
      |> visit(context.page)
      |> assert_has(main(), text: "You are not a member of Wattle Creek")
      |> refute_has(make())
      |> refute_has(own())
      |> assert_has(feed(others(), "My phone"))
    end
  end

  describe "the page" do
    test "says how to subscribe, and that a calendar changes nothing", context do
      build_conn()
      |> sign_in(context.user)
      |> visit(context.page)
      |> assert_has(main() |> region("How to subscribe"), text: "changes nothing in Rescord")
    end

    test "is one link from the first page and from the tasks", context do
      conn = sign_in(build_conn(), context.user)
      short = context.organisation.short_name
      parts = main() |> navigation("The parts of Wattle Creek")

      assert conn |> visit(~p"/o/#{short}") |> href(parts |> link("See the calendar feeds")) ==
               context.page

      assert conn |> visit(~p"/o/#{short}/tasks") |> href(main() |> link("Calendar feeds")) ==
               context.page
    end

    test "sends away a person who is not signed in", context do
      build_conn() |> visit(context.page) |> assert_path("/")
    end
  end
end
