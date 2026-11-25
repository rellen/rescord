defmodule Rescord.Export.CSVTest do
  @moduledoc """
  Holds the CSV of the export (ADR 0054): RFC 4180 quoting, the byte order
  mark, each kind of value as text, and a text that a spreadsheet would run
  as a formula.
  """

  use ExUnit.Case, async: true

  alias Rescord.Export.CSV

  doctest CSV

  defp csv(header, rows), do: header |> CSV.encode(rows) |> IO.iodata_to_binary()

  test "starts with the byte order mark, and ends each row with CRLF" do
    assert csv(["a", "b"], [[1, 2], [3, 4]]) == "﻿a,b\r\n1,2\r\n3,4\r\n"
  end

  test "quotes a cell with a comma, a quote or a line break, and doubles each quote" do
    assert CSV.cell("plain") == "plain"
    assert CSV.cell("a, b") == ~s("a, b")
    assert CSV.cell(~s(the "best" one)) == ~s("the ""best"" one")
    assert CSV.cell("two\nlines") == ~s("two\nlines")
    assert CSV.cell("two\r\nlines") == ~s("two\r\nlines")
  end

  test "writes each kind of value as text" do
    assert CSV.cell(nil) == ""
    assert CSV.cell(true) == "true"
    assert CSV.cell(:in_care) == "in_care"
    assert CSV.cell(42) == "42"
    assert CSV.cell(Decimal.new("2.50")) == "2.50"
    assert CSV.cell(~D[2026-11-25]) == "2026-11-25"
    assert CSV.cell(~T[08:30:00]) == "08:30:00"
    assert CSV.cell(~U[2026-11-25 08:30:00Z]) == "2026-11-25T08:30:00Z"
    assert CSV.cell(Ash.CiString.new("Someone@Example.org")) == "Someone@Example.org"
    assert CSV.cell([:monday, :friday]) == "monday; friday"
    assert CSV.cell(%{"every" => 2}) == ~s("{""every"":2}")
  end

  test "an instant in another zone is written in UTC" do
    instant =
      DateTime.new!(~D[2026-11-25], ~T[10:00:00], "Australia/Brisbane", Tz.TimeZoneDatabase)

    assert CSV.cell(instant) == "2026-11-25T00:00:00Z"
  end

  test "a text that a spreadsheet would run as a formula gets a ' before it" do
    for text <- ["=SUM(A1:A9)", "+61 400 000 000", "-Bob", "@cmd", "\tx", "\rx"] do
      assert String.starts_with?(CSV.cell(text), ["'", ~s("')]), inspect(text)
    end

    # A number keeps its sign, and a text that only holds the sign later keeps it.
    assert CSV.cell(Decimal.new("-5")) == "-5"
    assert CSV.cell(-3) == "-3"
    assert CSV.cell("A-1") == "A-1"
  end

  test "a struct with fields of Ash becomes JSON without them" do
    value = %{name: "Biscuit", __meta__: :x, other: %Ash.NotLoaded{}}
    assert CSV.cell(value) == ~s("{""name"":""Biscuit""}")
  end
end
