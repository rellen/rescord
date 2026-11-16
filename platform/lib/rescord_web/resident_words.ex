defmodule RescordWeb.ResidentWords do
  @moduledoc """
  The words that a page uses for the fixed lists of a resident: the status,
  the sex, the desex status, and the kinds of arrival and departure.

  A page never shows the atom of a value. Each list here has a word for each
  value, and `RescordWeb.ResidentWordsTest` holds the lists to the types.
  """

  @status [
    expected: {"Expected", "none"},
    in_care: {"In care", "ok"},
    away: {"Away for a time", "info"},
    left: {"Left", "none"}
  ]

  @kin [mother: "Mother", father: "Father"]
  @sex [female: "Female", male: "Male", unknown: "Not known"]
  @desex [entire: "Entire", desexed: "Desexed", unknown: "Not known"]

  @arrival [
    surrender: "Surrender by an owner",
    stray: "Stray",
    seizure: "Seizure by an authority",
    born_in_care: "Birth in care",
    transfer_in: "Transfer from another organisation"
  ]

  @departure [
    death: "Death",
    release: "Release",
    transfer_out: "Transfer to another organisation"
  ]

  @doc "The word for a status."
  def status(value), do: @status |> Keyword.fetch!(value) |> elem(0)

  @doc "The kind of state that `<.state>` draws for a status."
  def status_kind(value), do: @status |> Keyword.fetch!(value) |> elem(1)

  def kin(value), do: Keyword.fetch!(@kin, value)
  def sex(value), do: Keyword.fetch!(@sex, value)
  def desex(value), do: Keyword.fetch!(@desex, value)
  def arrival(value), do: Keyword.fetch!(@arrival, value)
  def departure(value), do: Keyword.fetch!(@departure, value)

  @doc "The options of a select for a list, each as `{word, value}`."
  def options(:status),
    do: Enum.map(@status, fn {value, {word, _kind}} -> {word, Atom.to_string(value)} end)

  def options(:kin), do: options_of(@kin)
  def options(:sex), do: options_of(@sex)
  def options(:desex), do: options_of(@desex)
  def options(:arrival), do: options_of(@arrival)
  def options(:departure), do: options_of(@departure)

  @doc "The values of a list, for the test that holds the words to the types."
  def values(:status), do: Keyword.keys(@status)
  def values(:kin), do: Keyword.keys(@kin)
  def values(:sex), do: Keyword.keys(@sex)
  def values(:desex), do: Keyword.keys(@desex)
  def values(:arrival), do: Keyword.keys(@arrival)
  def values(:departure), do: Keyword.keys(@departure)

  defp options_of(words),
    do: Enum.map(words, fn {value, word} -> {word, Atom.to_string(value)} end)

  @doc "A date in words, for example `12 September 2026`."
  def date(%Date{} = date), do: Calendar.strftime(date, "%-d %B %Y")
  def date(nil), do: nil

  @doc """
  The age of a resident on a day, in words: `about 20 months`, `3 years`.
  `nil` when the date of birth is not recorded.
  """
  def age(nil, _today), do: nil

  def age(%Date{} = born_on, %Date{} = today) do
    months = (today.year - born_on.year) * 12 + today.month - born_on.month
    months = if today.day < born_on.day, do: months - 1, else: months

    cond do
      months < 0 -> nil
      months < 1 -> plural(Date.diff(today, born_on), "day")
      months < 24 -> plural(months, "month")
      true -> plural(div(months, 12), "year")
    end
  end

  defp plural(1, word), do: "1 #{word}"
  defp plural(count, word), do: "#{count} #{word}s"
end
