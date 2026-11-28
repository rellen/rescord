defmodule RescordWeb.InsightWords do
  @moduledoc """
  The words of the pages of insights (ADR 0116): the counts of a day of
  tasks, a share in percent, and the sentences that say what a chart
  shows. A page never shows a count that is not in words somewhere.
  """

  alias RescordWeb.JournalWords

  @doc """
  The counts of the tasks of one day in words: how many of the tasks whose
  time has come were done on time, then the others that there are.

      iex> RescordWeb.InsightWords.day(%{total: 9, on_time: 6, late: 1, skipped: 1, overdue: 1, upcoming: 0})
      "6 of 9 on time, 1 late, 1 skipped, 1 overdue"

      iex> RescordWeb.InsightWords.day(%{total: 4, on_time: 1, late: 0, skipped: 0, overdue: 0, upcoming: 3})
      "1 of 1 on time, 3 to come"

      iex> RescordWeb.InsightWords.day(%{total: 2, on_time: 0, late: 0, skipped: 0, overdue: 0, upcoming: 2})
      "2 to come"

      iex> RescordWeb.InsightWords.day(%{total: 0, on_time: 0, late: 0, skipped: 0, overdue: 0, upcoming: 0})
      "No task"
  """
  @spec day(map) :: String.t()
  def day(%{total: 0}), do: "No task"

  def day(%{total: total, upcoming: upcoming}) when total == upcoming,
    do: "#{JournalWords.number(upcoming)} to come"

  def day(counts) do
    due = counts.total - counts.upcoming

    others =
      for {key, word} <- [
            late: "late",
            skipped: "skipped",
            overdue: "overdue",
            upcoming: "to come"
          ],
          counts[key] > 0,
          do: "#{JournalWords.number(counts[key])} #{word}"

    Enum.join(
      ["#{JournalWords.number(counts.on_time)} of #{JournalWords.number(due)} on time"] ++ others,
      ", "
    )
  end

  @doc """
  A part of a whole in percent, to the nearest whole percent. A share
  below 100% is never written as 100%, and one above none never as 0%.

      iex> RescordWeb.InsightWords.percent(7, 8)
      "88%"

      iex> RescordWeb.InsightWords.percent(999, 1000)
      "99%"

      iex> RescordWeb.InsightWords.percent(1, 1000)
      "1%"
  """
  @spec percent(non_neg_integer, pos_integer) :: String.t()
  def percent(part, whole) when is_integer(part) and is_integer(whole) and whole > 0 do
    rounded = round(part * 100 / whole)

    shown =
      cond do
        part < whole and rounded == 100 -> 99
        part > 0 and rounded == 0 -> 1
        true -> rounded
      end

    "#{shown}%"
  end

  @doc "A count of tasks: `1 task`, `2,410 tasks`."
  @spec tasks(non_neg_integer) :: String.t()
  def tasks(1), do: "1 task"
  def tasks(count), do: "#{JournalWords.number(count)} tasks"

  @doc "A count of residents: `1 resident`, `24 residents`."
  @spec residents(non_neg_integer) :: String.t()
  def residents(1), do: "1 resident"
  def residents(count), do: "#{JournalWords.number(count)} residents"

  @doc """
  How many residents are in care, as the start of a sentence.

      iex> RescordWeb.InsightWords.in_care(1)
      "1 resident is in care"

      iex> RescordWeb.InsightWords.in_care(0)
      "No resident is in care"
  """
  @spec in_care(non_neg_integer) :: String.t()
  def in_care(0), do: "No resident is in care"
  def in_care(1), do: "1 resident is in care"
  def in_care(count), do: "#{JournalWords.number(count)} residents are in care"

  @doc "A count of days: `1 day`, `12 days`."
  @spec days(non_neg_integer) :: String.t()
  def days(1), do: "1 day"
  def days(count), do: "#{JournalWords.number(count)} days"
end
