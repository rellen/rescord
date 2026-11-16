defmodule RescordWeb.JournalWordsTest do
  @moduledoc """
  Holds the words of the journal to the fixed lists: each kind of entry and
  each route has a word, and the words name no value that the list does not
  have.
  """

  use ExUnit.Case, async: true

  alias Rescord.Journal
  alias RescordWeb.JournalWords

  test "each kind of entry has a word" do
    assert Enum.sort(JournalWords.values(:kind)) == Enum.sort(Journal.EntryKind.values())

    for kind <- Journal.EntryKind.values() do
      refute JournalWords.kind(kind) =~ "_"
      assert JournalWords.kind_of(Atom.to_string(kind)) == kind
    end

    assert JournalWords.kind_of("no_such_kind") == nil
    assert JournalWords.kind_of(nil) == nil
  end

  test "each route has words" do
    assert Enum.sort(JournalWords.values(:route)) == Enum.sort(Journal.Route.values())
    for route <- Journal.Route.values(), do: assert(is_binary(JournalWords.route(route)))
  end

  test "a number has a comma for each thousand, and no zeros after the point" do
    assert JournalWords.number(Decimal.new("1095")) == "1,095"
    assert JournalWords.number(Decimal.new("640")) == "640"
    assert JournalWords.number(Decimal.new("38.50")) == "38.5"
    assert JournalWords.number(Decimal.new("1234567.25")) == "1,234,567.25"
    assert JournalWords.number(Decimal.new("1000")) == "1,000"
  end

  test "the facts of an entry are one line" do
    assert JournalWords.facts(%{
             measurement: %{
               measure_kind: %{label: "Weight"},
               unit: %{label: "g"},
               value: Decimal.new("1095")
             }
           }) == "Weight: 1,095 g"

    assert JournalWords.facts(%{
             prescription: %{
               medication: "A sample antibiotic",
               dose: "0.2 mL two times each day",
               route: :oral,
               starts_on: ~D[2026-11-12],
               ends_on: ~D[2026-11-16]
             }
           }) ==
             "A sample antibiotic, 0.2 mL two times each day, by mouth, 12 November 2026 to 16 November 2026"

    assert JournalWords.facts(%{
             dose: %{prescription: %{medication: "A sample antibiotic"}, amount: "0.2 mL"}
           }) ==
             "A sample antibiotic: 0.2 mL"

    assert JournalWords.facts(%{dose: %{prescription: nil, amount: nil}}) == nil
    assert JournalWords.facts(%{note: "Ate well."}) == nil
  end

  test "a time is a date and a time of day" do
    assert JournalWords.time(~U[2026-11-16 08:05:00Z]) == "16 November 2026, 08:05"
  end
end
