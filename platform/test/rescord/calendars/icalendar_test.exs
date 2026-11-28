defmodule Rescord.Calendars.ICalendarTest do
  @moduledoc """
  Holds the text of a calendar to the format of RFC 5545 (ADR 0074): the
  lines and their ends, the fold of a long line, the escapes of a text
  value, an instant and a day, and the value that says that a calendar
  changed.
  """

  use ExUnit.Case, async: true

  alias Rescord.Calendars.ICalendar

  @now ~U[2026-11-28 05:00:00Z]
  @calendar %{name: "Wattle Creek", time_zone: "Australia/Brisbane"}

  defp task(more \\ %{}) do
    Map.merge(
      %{
        uid: "task-1@example.org",
        starts: ~U[2026-11-29 22:30:00Z],
        minutes: 15,
        summary: "Feed the herd"
      },
      more
    )
  end

  # The lines of a text, with each fold put back together.
  defp lines(text) do
    text |> String.replace("\r\n ", "") |> String.split("\r\n", trim: true)
  end

  describe "a calendar" do
    test "starts and ends as the format says, and names itself" do
      lines = lines(ICalendar.encode(@calendar, [], @now))

      assert hd(lines) == "BEGIN:VCALENDAR"
      assert List.last(lines) == "END:VCALENDAR"
      assert "VERSION:2.0" in lines
      assert "PRODID:-//Rescord//Calendar feed//EN" in lines
      assert "METHOD:PUBLISH" in lines
      assert "NAME:Wattle Creek" in lines
      assert "X-WR-CALNAME:Wattle Creek" in lines
      assert "X-WR-TIMEZONE:Australia/Brisbane" in lines
      assert "REFRESH-INTERVAL;VALUE=DURATION:PT1H" in lines
      assert "X-PUBLISHED-TTL:PT1H" in lines
    end

    test "ends each line with CRLF, and has no bare end of a line" do
      text = ICalendar.encode(@calendar, [task(%{description: "One\nTwo"})], @now)

      assert String.ends_with?(text, "END:VCALENDAR\r\n")
      assert text |> String.replace("\r\n", "") |> String.contains?(["\r", "\n"]) == false
    end

    test "with no time zone says none" do
      text = ICalendar.encode(%{name: "Wattle Creek"}, [], @now)
      refute text =~ "X-WR-TIMEZONE"
    end
  end

  describe "an event at a time" do
    test "has its instant in UTC, its length, and the instant of the text" do
      lines = lines(ICalendar.encode(@calendar, [task()], @now))

      assert "BEGIN:VEVENT" in lines
      assert "UID:task-1@example.org" in lines
      assert "DTSTAMP:20261128T050000Z" in lines
      assert "DTSTART:20261129T223000Z" in lines
      assert "DURATION:PT15M" in lines
      assert "SUMMARY:Feed the herd" in lines
      assert "TRANSP:TRANSPARENT" in lines
      assert "END:VEVENT" in lines
      refute Enum.any?(lines, &String.starts_with?(&1, "DTEND"))
    end

    test "of another zone is the same instant in UTC" do
      {:ok, local} = DateTime.new(~D[2026-11-30], ~T[08:30:00], "Australia/Brisbane")
      lines = lines(ICalendar.encode(@calendar, [task(%{starts: local})], @now))

      assert "DTSTART:20261129T223000Z" in lines
    end

    test "has what a person reads when they open it" do
      event =
        task(%{
          description: "Kind: Feed\nFor: Biscuit",
          url: "https://example.org/o/wattle/tasks?day=2026-11-30#task-1",
          categories: ["Feed", "Morning, early"],
          status: :cancelled
        })

      lines = lines(ICalendar.encode(@calendar, [event], @now))

      assert "DESCRIPTION:Kind: Feed\\nFor: Biscuit" in lines
      assert "URL:https://example.org/o/wattle/tasks?day=2026-11-30#task-1" in lines
      assert "CATEGORIES:Feed,Morning\\, early" in lines
      assert "STATUS:CANCELLED" in lines
    end

    test "leaves out what it does not have, and an address that is not one line" do
      event = task(%{description: nil, url: "https://example.org/\r\nATTENDEE:x", categories: []})
      lines = lines(ICalendar.encode(@calendar, [event], @now))

      refute Enum.any?(lines, &String.starts_with?(&1, "DESCRIPTION"))
      refute Enum.any?(lines, &String.starts_with?(&1, "URL"))
      refute Enum.any?(lines, &String.starts_with?(&1, "CATEGORIES"))
      refute Enum.any?(lines, &String.starts_with?(&1, "ATTENDEE"))
    end
  end

  describe "an event of a whole day" do
    test "has a date, and ends on the next day" do
      event = %{uid: "lot-1@example.org", starts: ~D[2026-12-31], summary: "Expires: hay"}
      lines = lines(ICalendar.encode(@calendar, [event], @now))

      assert "DTSTART;VALUE=DATE:20261231" in lines
      assert "DTEND;VALUE=DATE:20270101" in lines
      refute Enum.any?(lines, &String.starts_with?(&1, "DURATION"))
    end
  end

  describe "a text value" do
    test "escapes the backslash, the semicolon, the comma and the end of a line" do
      assert ICalendar.escape("a\\b; c, d\ne") == "a\\\\b\\; c\\, d\\ne"
      assert ICalendar.escape("one\r\ntwo\rthree") == "one\\ntwo\\nthree"
    end

    test "loses each control character but the tab" do
      assert ICalendar.escape("a\u0000b\u0007c\td\u007Fe") == "abc\tde"
    end

    test "of a person cannot start a line of its own" do
      event = task(%{summary: "Feed\r\nEND:VEVENT\r\nBEGIN:VEVENT"})
      text = ICalendar.encode(@calendar, [event], @now)

      assert text =~ "SUMMARY:Feed\\nEND:VEVENT\\nBEGIN:VEVENT\r\n"
      assert length(Regex.scan(~r/^BEGIN:VEVENT\r$/m, text)) == 1
    end
  end

  describe "a long line" do
    test "is folded in parts of 75 octets at most, and reads the same" do
      summary = String.duplicate("Give the herd its hay. ", 12)
      text = ICalendar.encode(@calendar, [task(%{summary: summary})], @now)

      for line <- String.split(text, "\r\n") do
        assert byte_size(line) <= 75, "#{inspect(line)} is #{byte_size(line)} octets"
      end

      assert ("SUMMARY:" <> summary) in lines(text)
    end

    test "is never folded inside a character" do
      # Each of these characters is 3 or 4 octets.
      summary = String.duplicate("猫🐹", 30)
      text = ICalendar.encode(@calendar, [task(%{summary: summary})], @now)

      for line <- String.split(text, "\r\n") do
        assert String.valid?(line)
        assert byte_size(line) <= 75
      end

      assert ("SUMMARY:" <> summary) in lines(text)
    end

    test "of 75 octets is not folded, and one of 76 is" do
      exact = String.duplicate("a", 75)
      assert IO.iodata_to_binary(ICalendar.fold(exact)) == exact

      over = String.duplicate("a", 76)
      assert IO.iodata_to_binary(ICalendar.fold(over)) == exact <> "\r\n a"
    end
  end

  describe "the fingerprint of a calendar" do
    test "is the same at each instant, and changes with an event" do
      events = [task()]

      assert ICalendar.fingerprint(@calendar, events) == ICalendar.fingerprint(@calendar, events)

      assert ICalendar.encode(@calendar, events, @now) !=
               ICalendar.encode(@calendar, events, DateTime.add(@now, 60))

      refute ICalendar.fingerprint(@calendar, events) ==
               ICalendar.fingerprint(@calendar, [task(%{summary: "Feed the herd again"})])

      refute ICalendar.fingerprint(@calendar, events) ==
               ICalendar.fingerprint(%{@calendar | name: "Banksia Rise"}, events)
    end
  end
end
