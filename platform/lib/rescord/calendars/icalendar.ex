defmodule Rescord.Calendars.ICalendar do
  @moduledoc """
  Writes a calendar as iCalendar text (RFC 5545), which a calendar app
  reads from the address of a feed (ADR 0074).

  This module knows nothing of Rescord: it takes a calendar and a list of
  events, and gives the text. It holds the rules of the format:

    * each line ends with `CRLF`;
    * a line is 75 octets at most, and a longer one is folded: the next
      part starts on a new line with one space. A fold never splits a
      character;
    * a text value escapes the backslash, the semicolon, the comma and the
      end of a line, and holds no other control character;
    * an instant is in UTC, so the text needs no `VTIMEZONE`;
    * an event of a whole day has a date, and ends on the next day.

  An event has no alarm. Calendar apps often ignore the alarms of a calendar
  that they subscribe to.
  """

  @typedoc """
  The calendar: its name, and the time zone that an app shows it in when
  the person chose none.
  """
  @type calendar :: %{required(:name) => String.t(), optional(:time_zone) => String.t() | nil}

  @typedoc """
  One event.

    * `uid` - a name that no other event of any calendar has, and that
      stays the same each time that the calendar is written;
    * `starts` - an instant for an event at a time, or a date for an event
      of the whole day;
    * `minutes` - how long an event at a time is. An event of a day is one
      day;
    * `summary` - the line that a calendar shows;
    * `description`, `url`, `categories` - what a person reads when they
      open the event;
    * `status` - `:cancelled` for a thing that will not happen.
  """
  @type event :: %{
          required(:uid) => String.t(),
          required(:starts) => DateTime.t() | Date.t(),
          required(:summary) => String.t(),
          optional(:minutes) => pos_integer,
          optional(:description) => String.t() | nil,
          optional(:url) => String.t() | nil,
          optional(:categories) => [String.t()],
          optional(:status) => :confirmed | :cancelled
        }

  # A line holds this number of octets at most, without its `CRLF`.
  @line 75

  # The time between two reads that the calendar asks of an app.
  @refresh "PT1H"

  @doc """
  The text of a calendar with its events, in the order of the list. `now`
  is the instant at which the text is made: each event says it.
  """
  @spec encode(calendar, [event], DateTime.t()) :: String.t()
  def encode(%{name: name} = calendar, events, %DateTime{} = now) when is_list(events) do
    stamp = instant(now)

    head = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Rescord//Calendar feed//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:PUBLISH",
      "NAME:" <> escape(name),
      "X-WR-CALNAME:" <> escape(name),
      time_zone(calendar[:time_zone]),
      "REFRESH-INTERVAL;VALUE=DURATION:" <> @refresh,
      "X-PUBLISHED-TTL:" <> @refresh
    ]

    lines = head ++ Enum.map(events, &event(&1, stamp)) ++ ["END:VCALENDAR"]

    lines
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&[fold(&1), "\r\n"])
    |> IO.iodata_to_binary()
  end

  @doc """
  A value that changes when the calendar or one of its events changes, and
  not with the instant at which the text is made. Two reads of a calendar
  that did not change give the same one.
  """
  @spec fingerprint(calendar, [event]) :: String.t()
  def fingerprint(calendar, events) do
    text = encode(calendar, events, ~U[1970-01-01 00:00:00Z])

    :sha256
    |> :crypto.hash(text)
    |> binary_part(0, 16)
    |> Base.url_encode64(padding: false)
  end

  defp time_zone(zone) when is_binary(zone), do: "X-WR-TIMEZONE:" <> escape(zone)
  defp time_zone(_none), do: nil

  defp event(%{uid: uid, starts: starts, summary: summary} = event, stamp) do
    [
      "BEGIN:VEVENT",
      "UID:" <> escape(uid),
      "DTSTAMP:" <> stamp,
      span(starts, event[:minutes]),
      "SUMMARY:" <> escape(summary),
      text("DESCRIPTION", event[:description]),
      address(event[:url]),
      categories(event[:categories]),
      status(event[:status]),
      # An event of a feed takes no time of the person: it is not busy.
      "TRANSP:TRANSPARENT",
      "END:VEVENT"
    ]
  end

  # An event at a time, with its length. With no length it is an instant.
  defp span(%DateTime{} = starts, minutes) when is_integer(minutes) and minutes > 0,
    do: ["DTSTART:" <> instant(starts), "DURATION:PT#{minutes}M"]

  defp span(%DateTime{} = starts, _none), do: ["DTSTART:" <> instant(starts)]

  # An event of a whole day ends at the start of the next day.
  defp span(%Date{} = starts, _minutes) do
    [
      "DTSTART;VALUE=DATE:" <> day(starts),
      "DTEND;VALUE=DATE:" <> day(Date.add(starts, 1))
    ]
  end

  defp text(_name, value) when value in [nil, ""], do: nil
  defp text(name, value) when is_binary(value), do: name <> ":" <> escape(value)

  # An address is not a text value, so it has no escapes. It is one line.
  defp address(url) when is_binary(url) and url != "" do
    if String.match?(url, ~r/[\x00-\x20\x7F]/), do: nil, else: "URL:" <> url
  end

  defp address(_none), do: nil

  defp categories([_ | _] = names), do: "CATEGORIES:" <> Enum.map_join(names, ",", &escape/1)
  defp categories(_none), do: nil

  defp status(:cancelled), do: "STATUS:CANCELLED"
  defp status(:confirmed), do: "STATUS:CONFIRMED"
  defp status(_none), do: nil

  defp instant(%DateTime{} = instant) do
    instant
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  defp day(%Date{} = date), do: Calendar.strftime(date, "%Y%m%d")

  @doc """
  A text value with its escapes: `\\\\` for a backslash, `\\;`, `\\,` and
  `\\n` for the end of a line. A control character other than a tab goes.
  """
  @spec escape(String.t()) :: String.t()
  def escape(text) when is_binary(text) do
    text
    |> String.replace(~r/\r\n?/, "\n")
    |> String.replace(~r/[\x00-\x08\x0B-\x1F\x7F]/, "")
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end

  @doc """
  A line as the format wants it: parts of 75 octets at most, each part
  after the first on a new line that starts with one space.
  """
  @spec fold(String.t()) :: iodata
  def fold(line) when byte_size(line) <= @line, do: line
  def fold(line), do: line |> parts(@line) |> Enum.intersperse("\r\n ")

  # The space that starts each later part counts in its 75 octets.
  defp parts(text, room) do
    case take(text, room, "") do
      {part, ""} -> [part]
      {part, rest} -> [part | parts(rest, @line - 1)]
    end
  end

  # Whole characters that fit in `room` octets, and the rest of the text.
  defp take(text, room, taken) do
    case String.next_codepoint(text) do
      {point, rest} when byte_size(point) <= room ->
        take(rest, room - byte_size(point), taken <> point)

      _full_or_the_end ->
        {taken, text}
    end
  end
end
