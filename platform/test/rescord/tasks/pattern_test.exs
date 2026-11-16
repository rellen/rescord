defmodule Rescord.Tasks.PatternTest do
  @moduledoc """
  Holds the days of each pattern of a routine (ADR 0033). The module under
  test has no database and no clock, so these tests run beside others.
  """

  use ExUnit.Case, async: true

  alias Rescord.Tasks.Pattern

  doctest Pattern

  defp routine(facts) do
    Map.merge(
      %{pattern: :daily, every: nil, weekdays: [], starts_on: ~D[2026-11-01], ends_on: nil},
      facts
    )
  end

  test "each day is each date from the first to the last, the two included" do
    assert Pattern.dates(routine(%{}), ~D[2026-11-16], ~D[2026-11-18]) ==
             [~D[2026-11-16], ~D[2026-11-17], ~D[2026-11-18]]

    assert Pattern.dates(routine(%{}), ~D[2026-11-16], ~D[2026-11-16]) == [~D[2026-11-16]]
  end

  test "a routine has no day before its first day, or after its last day" do
    routine = routine(%{starts_on: ~D[2026-11-17], ends_on: ~D[2026-11-19]})

    assert Pattern.dates(routine, ~D[2026-11-10], ~D[2026-11-30]) ==
             [~D[2026-11-17], ~D[2026-11-18], ~D[2026-11-19]]

    assert Pattern.dates(routine, ~D[2026-11-20], ~D[2026-11-30]) == []
    assert Pattern.dates(routine, ~D[2026-11-01], ~D[2026-11-16]) == []
  end

  test "a first date after the last date has no day" do
    assert Pattern.dates(routine(%{}), ~D[2026-11-18], ~D[2026-11-16]) == []
  end

  test "the days of the week are those of the routine: 1 is Monday" do
    # 16 November 2026 is a Monday.
    routine = routine(%{pattern: :weekly, weekdays: [1, 3, 7]})

    assert Pattern.dates(routine, ~D[2026-11-16], ~D[2026-11-29]) == [
             ~D[2026-11-16],
             ~D[2026-11-18],
             ~D[2026-11-22],
             ~D[2026-11-23],
             ~D[2026-11-25],
             ~D[2026-11-29]
           ]
  end

  test "every number of days counts from the first day of the routine" do
    routine = routine(%{pattern: :interval, every: 3, starts_on: ~D[2026-11-10]})

    assert Pattern.dates(routine, ~D[2026-11-10], ~D[2026-11-20]) ==
             [~D[2026-11-10], ~D[2026-11-13], ~D[2026-11-16], ~D[2026-11-19]]

    # The days do not move with the first date that the caller asks for.
    assert Pattern.dates(routine, ~D[2026-11-14], ~D[2026-11-20]) ==
             [~D[2026-11-16], ~D[2026-11-19]]
  end

  test "every number of months is on the day of the month of the first day" do
    routine = routine(%{pattern: :monthly, every: 3, starts_on: ~D[2026-11-16]})

    assert Pattern.dates(routine, ~D[2026-11-01], ~D[2027-12-31]) ==
             [~D[2026-11-16], ~D[2027-02-16], ~D[2027-05-16], ~D[2027-08-16], ~D[2027-11-16]]

    # Each year.
    assert Pattern.dates(%{routine | every: 12}, ~D[2027-01-01], ~D[2028-12-31]) ==
             [~D[2027-11-16], ~D[2028-11-16]]
  end

  test "a month with no such day has the routine on its last day, and the next month is not early" do
    routine = routine(%{pattern: :monthly, every: 1, starts_on: ~D[2027-01-31]})

    assert Pattern.dates(routine, ~D[2027-01-01], ~D[2027-05-31]) ==
             [~D[2027-01-31], ~D[2027-02-28], ~D[2027-03-31], ~D[2027-04-30], ~D[2027-05-31]]
  end

  test "a pattern with a fact that is not there has no day" do
    for facts <- [%{pattern: :interval, every: nil}, %{pattern: :monthly, every: 0}] do
      assert Pattern.dates(routine(facts), ~D[2026-11-16], ~D[2026-11-30]) == []
    end

    assert Pattern.dates(
             routine(%{pattern: :weekly, weekdays: []}),
             ~D[2026-11-16],
             ~D[2026-11-30]
           ) ==
             []
  end
end
