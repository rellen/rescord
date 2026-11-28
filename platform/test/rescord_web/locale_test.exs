defmodule RescordWeb.LocaleTest do
  @moduledoc """
  The forms of a date, a time of day and a number in each locale that
  Rescord offers (ADR 0075).
  """

  use ExUnit.Case, async: true

  alias RescordWeb.Locale

  doctest RescordWeb.Locale

  # {tag, date, day, time, number}
  @forms [
    {"en-AU", "16 November 2026", "Monday, 16 November 2026", "6:30 pm", "1,234,567.5"},
    {"en-CA", "November 16, 2026", "Monday, November 16, 2026", "6:30 p.m.", "1,234,567.5"},
    {"en-GB", "16 November 2026", "Monday, 16 November 2026", "18:30", "1,234,567.5"},
    {"en-IE", "16 November 2026", "Monday 16 November 2026", "18:30", "1,234,567.5"},
    {"en-IN", "16 November 2026", "Monday, 16 November 2026", "6:30 PM", "12,34,567.5"},
    {"en-NZ", "16 November 2026", "Monday, 16 November 2026", "6:30 pm", "1,234,567.5"},
    {"en-US", "November 16, 2026", "Monday, November 16, 2026", "6:30 PM", "1,234,567.5"},
    {"en-ZA", "16 November 2026", "Monday, 16 November 2026", "18:30", "1 234 567,5"},
    {"en-001", "16 November 2026", "Monday, 16 November 2026", "6:30 pm", "1,234,567.5"}
  ]

  test "the table here has each locale that Rescord offers" do
    assert Enum.sort(for {tag, _, _, _, _} <- @forms, do: tag) ==
             Enum.sort(for {tag, _name} <- Rescord.Accounts.locales(), do: tag)
  end

  for {tag, date, day, time, number} <- @forms do
    test "the forms of #{tag}" do
      Locale.put(unquote(tag))

      assert Locale.current() == unquote(tag)
      assert Locale.date(~D[2026-11-16]) == unquote(date)
      assert Locale.day(~D[2026-11-16]) == unquote(day)
      assert Locale.time(~T[18:30:00]) == unquote(time)
      assert Locale.number(Decimal.new("1234567.50")) == unquote(number)
    end
  end

  test "a process with no locale has the default" do
    assert Locale.current() == Rescord.Accounts.default_locale()
    assert Locale.date(~D[2026-11-16]) == "16 November 2026"
  end

  test "an organisation sets the locale, and a tag that Rescord does not offer sets the default" do
    assert Locale.put(%{locale: "en-US"}) == :ok
    assert Locale.current() == "en-US"

    for other <- ["fr", "en-au", "", nil] do
      Locale.put("en-US")
      Locale.put(other)
      assert Locale.current() == "en-AU"
    end
  end

  test "the locale of a process does not reach its task" do
    Locale.put("en-US")
    assert Task.await(Task.async(fn -> Locale.current() end)) == "en-AU"
  end

  test "a number keeps each digit, and never rounds" do
    Locale.put("en-AU")

    assert Locale.number(Decimal.new("0.00025")) == "0.00025"

    assert Locale.number(Decimal.new("1234567.000000000000000000001")) ==
             "1,234,567.000000000000000000001"

    assert Locale.number(Decimal.new("38.50")) == "38.5"
    assert Locale.number(Decimal.new("1.0E+5")) == "100,000"
    assert Locale.number(Decimal.new("-0.5")) == "-0.5"
    assert Locale.number(Decimal.new("0")) == "0"
    assert Locale.number(Decimal.new("0.000")) == "0"
    assert Locale.number(-12) == "-12"
  end

  test "a value that is no number has its plain text" do
    assert Locale.number(Decimal.new("NaN")) == "NaN"
    assert Locale.number(Decimal.new("Infinity")) == "Infinity"
  end

  test "a time of day has a usual space, and a date and time are the date, a comma, the time" do
    Locale.put("en-US")

    refute Locale.time(~T[08:30:00]) =~ " "
    assert Locale.time(~T[08:30:59]) == "8:30 AM"

    local = DateTime.new!(~D[2026-11-16], ~T[08:30:00], "Australia/Brisbane")
    assert Locale.time(local) == "8:30 AM"
    assert Locale.date_time(local) == "November 16, 2026, 8:30 AM"
  end
end
