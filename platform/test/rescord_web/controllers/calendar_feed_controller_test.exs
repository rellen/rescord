defmodule RescordWeb.CalendarFeedControllerTest do
  @moduledoc """
  Holds the address of a calendar feed (ADR 0074): the calendar that a
  calendar app gets with the token and no session, the words of its events,
  the answer for a calendar that did not change, the one answer for each
  refusal, the limit of a client, and a log with no token.

  Each test creates an organisation, so the tests do not run beside others
  (see `Rescord.Accounts.OrganisationTest`).
  """

  use RescordWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures
  import Rescord.ResidentsFixtures

  alias Rescord.{Accounts, Calendars, Inventory, Locations, Residents, Tasks}
  alias RescordWeb.CalendarFeedController

  setup %{conn: conn} do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_, administrator} = member!(organisation, :administrator, root)
    {_, user} = member!(organisation, :member, administrator)

    # Each test counts its requests under a client address of its own, so
    # the tests share no count of the limit.
    number = System.unique_integer([:positive])
    conn = %{conn | remote_ip: {198, 18, rem(div(number, 256), 256), rem(number, 256)}}

    {:ok,
     conn: conn,
     root: root,
     organisation: organisation,
     administrator: administrator,
     user: user,
     today: Accounts.today(organisation),
     admin: [actor: administrator, tenant: organisation],
     options: [actor: user, tenant: organisation]}
  end

  defp feed!(context, attributes \\ %{}) do
    feed =
      Calendars.subscribe!(
        Map.merge(%{name: "My phone", tasks: :all}, attributes),
        context.options
      )

    {feed, Calendars.token(feed)}
  end

  defp feed_path(context, token),
    do: ~p"/o/#{context.organisation.short_name}/calendar.ics?#{[token: token]}"

  defp at(context, days, time) do
    day = Date.add(context.today, days)

    {:ok, instant} =
      Accounts.local_instant(context.organisation, "#{Date.to_iso8601(day)}T#{time}")

    instant
  end

  # The lines of a calendar, with each fold put back together.
  defp lines(body) do
    body |> String.replace("\r\n ", "") |> String.split("\r\n", trim: true)
  end

  # The lines of the event whose summary starts with `summary`.
  defp event(body, summary) do
    body
    |> lines()
    |> Enum.chunk_by(&(&1 == "BEGIN:VEVENT"))
    |> Enum.find(fn lines ->
      Enum.any?(lines, &String.starts_with?(&1, "SUMMARY:" <> summary))
    end)
  end

  describe "a calendar app with the token" do
    test "gets the calendar, with no session and no cookie", context do
      Tasks.plan_task!(%{title: "Morning feed", due_at: at(context, 1, "08:30")}, context.admin)
      {_feed, token} = feed!(context)

      conn = get(context.conn, feed_path(context, token))

      assert body = response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["text/calendar; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["private, no-cache"]
      assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
      assert [~s(W/") <> _tag] = get_resp_header(conn, "etag")
      assert get_resp_header(conn, "set-cookie") == []

      lines = lines(body)
      assert hd(lines) == "BEGIN:VCALENDAR"
      assert List.last(lines) == "END:VCALENDAR"
      assert "X-WR-CALNAME:My phone" in lines
      assert "X-WR-TIMEZONE:Australia/Brisbane" in lines
      assert "SUMMARY:Morning feed" in lines

      # 08:30 in Brisbane is 22:30 of the day before in UTC.
      day = context.today |> Calendar.strftime("%Y%m%d")
      assert "DTSTART:#{day}T223000Z" in lines
      assert "DURATION:PT15M" in lines
    end

    test "gets a task with its words, and a note only when the feed says so", context do
      lists = lists!(context.organisation, context.root)
      biscuit = resident!(lists, context.admin)

      task =
        Tasks.plan_task!(
          %{
            title: "Evening medication",
            note: "Half a tablet; with food",
            due_at: at(context, 0, "23:30"),
            kind_id: lists.task_kind.medicate,
            resident_ids: [biscuit.id],
            assignee_ids: [context.user.id]
          },
          context.admin
        )

      {_feed, plain} = feed!(context)
      {_feed, with_notes} = feed!(context, %{name: "With notes", with_notes: true})

      body = response(get(context.conn, feed_path(context, plain)), 200)
      event = event(body, "Evening medication")

      assert "SUMMARY:Evening medication (Biscuit)" in event
      assert "CATEGORIES:Medicate" in event
      assert "STATUS:CONFIRMED" in event
      assert "UID:task-#{task.id}@#{RescordWeb.Endpoint.host()}" in event

      link =
        "#{RescordWeb.Endpoint.url()}/o/#{context.organisation.short_name}/tasks" <>
          "?day=#{Date.to_iso8601(context.today)}#task-#{task.id}"

      assert "URL:#{link}" in event

      assert "DESCRIPTION:Kind: Medicate\\nFor: Biscuit\\nState: Due\\nOpen in Rescord: #{link}" in event

      # The feed never names a member, and has no note unless it says so.
      refute body =~ "Half a tablet"
      refute body =~ to_string(context.user.email)
      refute body =~ to_string(context.administrator.email)

      body = response(get(context.conn, feed_path(context, with_notes)), 200)
      text = body |> lines() |> Enum.join("\n")
      assert text =~ "State: Due\\nHalf a tablet\\; with food\\nOpen in Rescord"
      refute body =~ to_string(context.user.email)
    end

    test "gets the state of a task in words", context do
      done =
        Tasks.plan_task!(
          %{title: "Clean the hutch", due_at: at(context, 0, "07:00")},
          context.admin
        )

      skipped =
        Tasks.plan_task!(
          %{title: "Weigh the herd", due_at: at(context, 0, "07:30")},
          context.admin
        )

      {:ok, _} = Tasks.complete_task(done, %{}, context.options)
      {:ok, _} = Tasks.skip_task(skipped, %{skip_reason: "The scale is broken"}, context.options)

      {_feed, plain} = feed!(context)
      {_feed, with_notes} = feed!(context, %{name: "With notes", with_notes: true})

      body = response(get(context.conn, feed_path(context, plain)), 200)

      assert "STATUS:CONFIRMED" in event(body, "Done: Clean the hutch")
      assert Enum.any?(event(body, "Done: Clean the hutch"), &(&1 =~ "State: Done"))
      assert "STATUS:CANCELLED" in event(body, "Skipped: Weigh the herd")
      refute body =~ "The scale is broken"

      body = response(get(context.conn, feed_path(context, with_notes)), 200)
      assert body =~ "State: Skipped. The scale is broken"
    end

    test "gets the days of the residents and of the stock that the feed names", context do
      lists = lists!(context.organisation, context.root)
      fern = resident!(lists, context.admin, %{name: "Fern"})
      back_on = Date.add(context.today, 3)

      {:ok, absence} =
        Residents.start_absence(
          %{resident_id: fern.id, reason: "At the clinic", expected_back_on: back_on},
          context.admin
        )

      shed = Locations.add_location!(%{name: "Feed shed"}, context.admin)
      hay = Inventory.add_item!(%{name: "Meadow hay", unit_id: lists.unit.bag}, context.admin)
      expires_on = Date.add(context.today, 20)

      lot =
        Inventory.receive_lot!(
          %{
            item_id: hay.id,
            code: "B-1",
            quantity: 10,
            location_id: shed.id,
            expires_on: expires_on
          },
          context.admin
        )

      {_feed, tasks_only} = feed!(context)
      body = response(get(context.conn, feed_path(context, tasks_only)), 200)
      refute body =~ "Fern"
      refute body =~ "Meadow hay"

      {_feed, token} =
        feed!(context, %{name: "All of it", with_returns: true, with_expiry: true})

      body = response(get(context.conn, feed_path(context, token)), 200)
      home = "#{RescordWeb.Endpoint.url()}/o/#{context.organisation.short_name}"

      back = event(body, "Expected back: Fern")
      assert "UID:absence-#{absence.id}@#{RescordWeb.Endpoint.host()}" in back
      assert "DTSTART;VALUE=DATE:#{Calendar.strftime(back_on, "%Y%m%d")}" in back
      assert "DTEND;VALUE=DATE:#{Calendar.strftime(Date.add(back_on, 1), "%Y%m%d")}" in back
      assert "URL:#{home}/residents/#{fern.id}" in back
      refute body =~ "At the clinic"

      expiry = event(body, "Expires: Meadow hay (Lot B-1)")
      assert "UID:lot-#{lot.id}@#{RescordWeb.Endpoint.host()}" in expiry
      assert "DTSTART;VALUE=DATE:#{Calendar.strftime(expires_on, "%Y%m%d")}" in expiry
      assert "URL:#{home}/inventory/#{hay.id}" in expiry
      assert Enum.any?(expiry, &(&1 =~ "In stock: 10 bag"))
    end

    test "gets no body for a calendar that did not change", context do
      Tasks.plan_task!(%{title: "Morning feed", due_at: at(context, 1, "08:30")}, context.admin)
      {_feed, token} = feed!(context)

      conn = get(context.conn, feed_path(context, token))
      assert response(conn, 200)
      [tag] = get_resp_header(conn, "etag")

      for asked <- [tag, String.trim_leading(tag, "W/"), ~s("another", #{tag})] do
        conn =
          context.conn
          |> put_req_header("if-none-match", asked)
          |> get(feed_path(context, token))

        assert response(conn, 304) == ""
        assert get_resp_header(conn, "etag") == [tag]
      end

      Tasks.plan_task!(%{title: "Evening feed", due_at: at(context, 1, "17:30")}, context.admin)

      conn =
        context.conn
        |> put_req_header("if-none-match", tag)
        |> get(feed_path(context, token))

      assert response(conn, 200) =~ "SUMMARY:Evening feed"
      assert get_resp_header(conn, "etag") != [tag]
    end
  end

  describe "each refusal" do
    test "gets the same answer", context do
      {feed, token} = feed!(context)
      {revoked, revoked_token} = feed!(context, %{name: "Old phone"})
      :ok = Calendars.revoke_feed(revoked, context.options)
      short_name = context.organisation.short_name

      home = "/o/#{short_name}/calendar.ics"

      refusals = [
        home,
        home <> "?token=",
        home <> "?token=#{Calendars.Token.new()}",
        home <> "?token[]=#{token}",
        home <> "?token=#{revoked_token}",
        home <> "?token=#{feed.id}",
        "/o/no-such-refuge/calendar.ics?token=#{token}"
      ]

      answers =
        for path <- refusals do
          conn = get(context.conn, path)
          {conn.status, conn.resp_body, get_resp_header(conn, "content-type")}
        end

      assert Enum.uniq(answers) == [
               {404, "No calendar is at this address.\n", ["text/plain; charset=utf-8"]}
             ]

      # The feed itself still answers.
      assert response(get(context.conn, feed_path(context, token)), 200)
    end

    test "is the answer when the owner cannot have a feed any more", context do
      {_feed, token} = feed!(context)
      assert response(get(context.conn, feed_path(context, token)), 200)

      {:ok, member} = Accounts.member_of_user(context.user.id, context.admin)
      :ok = Accounts.remove_member(member, context.admin)

      assert response(get(context.conn, feed_path(context, token)), 404)
    end

    test "is the answer to a person who is signed in, with no token", context do
      conn =
        context.conn
        |> sign_in(context.user)
        |> get(~p"/o/#{context.organisation.short_name}/calendar.ics")

      assert response(conn, 404)
    end
  end

  describe "the limit of a client" do
    test "is 60 requests in a minute, and then the client waits", context do
      {_feed, token} = feed!(context)
      limit = CalendarFeedController.client_limit()
      assert limit == 60

      for _ <- 1..(limit - 1) do
        assert get(context.conn, feed_path(context, "no-token")).status == 404
      end

      assert response(get(context.conn, feed_path(context, token)), 200)

      conn = get(context.conn, feed_path(context, token))
      assert response(conn, 429) == "Too many requests. Ask again later.\n"
      assert [wait] = get_resp_header(conn, "retry-after")
      assert String.to_integer(wait) in 1..60

      # Another client is not held.
      other = %{context.conn | remote_ip: {198, 19, 0, 1}}
      assert response(get(other, feed_path(context, token)), 200)
    end
  end

  describe "the log" do
    setup do
      level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: level) end)
    end

    test "has the request, and never the token", context do
      {_feed, token} = feed!(context)

      log =
        capture_log(fn ->
          assert response(get(context.conn, feed_path(context, token)), 200)
          assert response(get(context.conn, feed_path(context, Calendars.Token.new())), 404)
        end)

      assert log =~ "/o/#{context.organisation.short_name}/calendar.ics"
      assert log =~ "[FILTERED]"
      # At the level `debug` a query shows the hash that it looks for. The
      # hash opens no feed, and the token is nowhere.
      refute log =~ token
    end
  end
end
