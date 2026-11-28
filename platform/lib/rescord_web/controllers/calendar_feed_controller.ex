defmodule RescordWeb.CalendarFeedController do
  @moduledoc """
  `GET /o/<short name>/calendar.ics?token=<token>` sends the calendar of a
  feed as iCalendar text (ADR 0074). A calendar app asks, on its own
  schedule.

  A calendar app cannot sign in, so the request has no session, and the
  token of the address is the key. `Rescord.Calendars.fetch/3` finds the
  feed and the member that it reads as, and the content is read as that
  member, so the policies decide what the calendar holds.

    * **One answer for each refusal.** An organisation that is not there, a
      token of no feed, a feed that was revoked and a member who cannot
      have a feed now all get the same 404.
    * **The token is in no log.** It is the parameter `token`, which the
      log of the parameters leaves out, and the path of the request has
      none.
    * **A limit.** One client address gets `@client_limit` answers in a
      minute, and then 429 with the time to wait (ADR 0020).
    * **Cheap to ask again.** The answer has an `ETag` that changes only
      with the content. A request that names it in `If-None-Match` gets
      304 and no body.
  """

  use RescordWeb, :controller

  alias Rescord.Calendars
  alias Rescord.Calendars.ICalendar
  alias RescordWeb.CalendarEvents

  # The requests of one client address in one period, for all feeds. A
  # calendar app reads a feed a few times in an hour at most.
  @client_limit 60
  @client_period :timer.minutes(1)

  @doc "The requests that one client address gets in one minute."
  @spec client_limit() :: pos_integer
  def client_limit, do: @client_limit

  def show(conn, params) do
    case Rescord.RateLimit.hit(client_key(conn), @client_period, @client_limit) do
      {:allow, _count} -> answer(conn, params)
      {:deny, wait} -> too_many(conn, wait)
    end
  end

  defp answer(conn, %{"organisation" => short_name, "token" => token}) do
    now = DateTime.utc_now()

    case Calendars.fetch(short_name, token, now) do
      {:ok, feed, user, organisation} ->
        # The words of an event, such as a dose, have the forms of the
        # organisation, as its pages do (ADR 0075).
        :ok = RescordWeb.Locale.put(organisation)

        # A fault in the read is a fault of Rescord, and not an empty calendar.
        {:ok, entries} = Calendars.entries(feed, user, organisation, now)

        send_calendar(
          conn,
          CalendarEvents.calendar(feed, organisation),
          CalendarEvents.events(entries, feed, organisation),
          now
        )

      :error ->
        not_found(conn)
    end
  end

  defp answer(conn, _params), do: not_found(conn)

  defp send_calendar(conn, calendar, events, now) do
    tag = ICalendar.fingerprint(calendar, events)

    conn =
      conn
      # The text says when it was made, so two answers with the same
      # content differ in that line: the tag is a weak one.
      |> put_resp_header("etag", ~s(W/"#{tag}"))
      |> headers()

    if tag in asked_tags(conn) do
      send_resp(conn, 304, "")
    else
      conn
      |> put_resp_content_type("text/calendar", "utf-8")
      |> put_resp_header("content-disposition", ~s(inline; filename="rescord.ics"))
      |> send_resp(200, ICalendar.encode(calendar, events, now))
    end
  end

  # The tags of `If-None-Match`, each without its quotes and its mark of a
  # weak tag.
  defp asked_tags(conn) do
    for header <- get_req_header(conn, "if-none-match"),
        tag <- String.split(header, ","),
        do: tag |> String.trim() |> String.trim_leading("W/") |> String.trim("\"")
  end

  # A calendar app keeps the answer and asks again with its tag. No shared
  # cache keeps it, no search engine lists it, and it names no page.
  defp headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-cache")
    |> put_resp_header("x-robots-tag", "noindex, nofollow")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  defp not_found(conn) do
    conn
    |> headers()
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(404, "No calendar is at this address.\n")
  end

  defp too_many(conn, wait) do
    conn
    |> headers()
    |> put_resp_header("retry-after", wait |> div(1000) |> max(1) |> to_string())
    |> put_resp_content_type("text/plain", "utf-8")
    |> send_resp(429, "Too many requests. Ask again later.\n")
  end

  defp client_key(conn) do
    "calendar/client/" <> (conn.remote_ip |> :inet.ntoa() |> to_string())
  end
end
