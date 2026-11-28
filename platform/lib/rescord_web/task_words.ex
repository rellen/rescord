defmodule RescordWeb.TaskWords do
  @moduledoc """
  The words that a page uses for where a task is: overdue, due, done or
  skipped, and for when a routine repeats. A page never shows the atom of a
  value.
  """

  alias RescordWeb.ResidentWords

  @weekdays [
    {"Monday", 1},
    {"Tuesday", 2},
    {"Wednesday", 3},
    {"Thursday", 4},
    {"Friday", 5},
    {"Saturday", 6},
    {"Sunday", 7}
  ]

  @patterns [
    daily: "Each day",
    weekly: "On given days of the week",
    interval: "Every number of days",
    monthly: "Every number of months"
  ]

  @phases [
    overdue: {"Overdue", "alert"},
    due: {"Due", "info"},
    done: {"Done", "ok"},
    skipped: {"Skipped", "none"}
  ]

  @doc "The word for a phase of a task."
  def phase(value), do: @phases |> Keyword.fetch!(value) |> elem(0)

  @doc "The kind of state that `<.state>` draws for a phase."
  def phase_kind(value), do: @phases |> Keyword.fetch!(value) |> elem(1)

  @doc """
  The states of a task as the choices of a filter: the words, and the value
  as text. Overdue is no state: it is a task that is due, past its time.
  """
  def state_options,
    do: for(state <- [:due, :done, :skipped], do: {phase(state), to_string(state)})

  @doc "The phases, for the test that holds the words."
  def phases, do: Keyword.keys(@phases)

  @doc """
  A day in words, with its day of the week, in the form of the locale of
  the page (ADR 0075): `Monday, 16 November 2026`.
  """
  def day(%Date{} = date), do: RescordWeb.Locale.day(date)

  @doc "A time of day, in the form of the locale of the page: `8:30 am`."
  def time(%DateTime{} = local), do: RescordWeb.Locale.time(local)
  def time(%Time{} = time), do: RescordWeb.Locale.time(time)

  @doc "The days of the week with their numbers: Monday is 1."
  def weekdays, do: @weekdays

  @doc "The patterns of a routine as the options of a select: the words, and the value as text."
  def pattern_options, do: for({value, words} <- @patterns, do: {words, to_string(value)})

  @doc "The patterns that have words, for the test that holds them."
  def patterns, do: Keyword.keys(@patterns)

  @doc """
  When a routine repeats, in words: `Each day`, `Each Monday and Friday`,
  `Every 3 days`, `Each month`, `Every 3 months`.
  """
  def pattern(%{pattern: :daily}), do: "Each day"

  def pattern(%{pattern: :weekly, weekdays: weekdays}) do
    names = for {name, number} <- @weekdays, number in weekdays, do: name
    "Each " <> join(names)
  end

  def pattern(%{pattern: :interval, every: 1, count_from: :last_done}),
    do: "1 day after the last task is done"

  def pattern(%{pattern: :interval, every: every, count_from: :last_done}),
    do: "#{every} days after the last task is done"

  def pattern(%{pattern: :interval, every: 1}), do: "Each day"
  def pattern(%{pattern: :interval, every: every}), do: "Every #{every} days"
  def pattern(%{pattern: :monthly, every: 1}), do: "Each month"
  def pattern(%{pattern: :monthly, every: every}), do: "Every #{every} months"

  @doc "The choices of the day from which a routine of every number of days counts."
  def count_from_options,
    do: [
      {"Its first day: the days do not move", "first_day"},
      {"The day when a member last finishes a task", "last_done"}
    ]

  @doc "The times of a routine: `8:00 am and 6:00 pm`."
  def times(times), do: times |> Enum.map(&time/1) |> join()

  @doc "The first and the last day of a routine: `From 16 November 2026`."
  def span(%{starts_on: starts_on, ends_on: nil}), do: "From #{ResidentWords.date(starts_on)}"

  def span(%{starts_on: starts_on, ends_on: ends_on}),
    do: "From #{ResidentWords.date(starts_on)} to #{ResidentWords.date(ends_on)}"

  @doc "A number of days: `1 day`, `14 days`."
  def days(1), do: "1 day"
  def days(number) when is_integer(number), do: "#{number} days"

  defp join([]), do: ""
  defp join([one]), do: one
  defp join(words), do: Enum.join(Enum.drop(words, -1), ", ") <> " and " <> List.last(words)
end
