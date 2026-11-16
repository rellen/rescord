defmodule Rescord.Tasks.Pattern do
  @moduledoc """
  The days of a routine: a pattern as dates, with no database and no clock.

  `dates/3` takes the pattern of a routine and gives each of its days from a
  first date to a last date, the two included. The dates are those of the
  calendar of the organisation: this module knows no time zone.

  ## Examples

      iex> routine = %{pattern: :weekly, weekdays: [1, 5], every: nil,
      ...>   starts_on: ~D[2026-11-01], ends_on: nil}
      iex> Rescord.Tasks.Pattern.dates(routine, ~D[2026-11-16], ~D[2026-11-22])
      [~D[2026-11-16], ~D[2026-11-20]]

      iex> routine = %{pattern: :monthly, every: 1, weekdays: [],
      ...>   starts_on: ~D[2026-01-31], ends_on: nil}
      iex> Rescord.Tasks.Pattern.dates(routine, ~D[2026-02-01], ~D[2026-04-30])
      [~D[2026-02-28], ~D[2026-03-31], ~D[2026-04-30]]
  """

  @typedoc "The part of a routine that says when it repeats."
  @type routine :: %{
          required(:pattern) => :daily | :weekly | :interval | :monthly,
          required(:every) => pos_integer | nil,
          required(:weekdays) => [1..7],
          required(:starts_on) => Date.t(),
          required(:ends_on) => Date.t() | nil,
          optional(atom) => term
        }

  @doc """
  Each day of a routine from `first` to `last`, the two included, in order.
  A routine has no day before its first day, or after its last day.
  """
  @spec dates(routine, Date.t(), Date.t()) :: [Date.t()]
  def dates(%{starts_on: starts_on, ends_on: ends_on} = routine, %Date{} = first, %Date{} = last) do
    first = Enum.max([first, starts_on], Date)
    last = if ends_on, do: Enum.min([last, ends_on], Date), else: last

    if Date.compare(first, last) == :gt, do: [], else: days(routine, first, last)
  end

  defp days(%{pattern: :daily}, first, last), do: Enum.to_list(Date.range(first, last))

  defp days(%{pattern: :weekly, weekdays: weekdays}, first, last) do
    Enum.filter(Date.range(first, last), &(Date.day_of_week(&1) in weekdays))
  end

  defp days(%{pattern: :interval, every: every, starts_on: starts_on}, first, last)
       when is_integer(every) and every > 0 do
    Enum.filter(Date.range(first, last), &(rem(Date.diff(&1, starts_on), every) == 0))
  end

  # Each day is a number of months after the first day, and not after the
  # day before it. So a routine that starts on the 31st is on the 31st of
  # each month that has one, and on the last day of each other month.
  defp days(%{pattern: :monthly, every: every, starts_on: starts_on}, first, last)
       when is_integer(every) and every > 0 do
    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&Date.shift(starts_on, month: &1 * every))
    |> Stream.take_while(&(Date.compare(&1, last) != :gt))
    |> Enum.filter(&(Date.compare(&1, first) != :lt))
  end

  # A pattern with a fact that is not there has no day.
  defp days(_routine, _first, _last), do: []
end
