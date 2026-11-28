defmodule RescordWeb.JournalWords do
  @moduledoc """
  The words that a page uses for the journal: the kind of an entry, the
  route of a medication, and the facts of an entry in one line.

  A page never shows the atom of a value. `RescordWeb.JournalWordsTest`
  holds the lists to the types.
  """

  alias RescordWeb.ResidentWords

  @kinds [
    examination: "Examination",
    diagnosis: "Diagnosis",
    measurement: "Measurement",
    procedure: "Procedure",
    vaccination: "Vaccination",
    prescription: "Prescription",
    dose: "Dose given",
    placement: "Placement",
    group: "Group",
    behaviour: "Behaviour",
    general: "General"
  ]

  @routes [
    oral: "by mouth",
    topical: "on the skin",
    injection: "by injection",
    eye: "in the eye",
    ear: "in the ear",
    other: "by another route"
  ]

  def kind(value), do: Keyword.fetch!(@kinds, value)
  def route(value), do: Keyword.fetch!(@routes, value)

  @doc "The options of a select, each as `{word, value}`."
  def options(:kind), do: Enum.map(@kinds, fn {value, word} -> {word, Atom.to_string(value)} end)

  def options(:route),
    do:
      Enum.map(@routes, fn {value, word} -> {String.capitalize(word), Atom.to_string(value)} end)

  @doc "The values of a list, for the test that holds the words to the types."
  def values(:kind), do: Keyword.keys(@kinds)
  def values(:route), do: Keyword.keys(@routes)

  @doc """
  The kind of an entry for the text of a form, or `nil`. This makes no atom
  from the text.
  """
  def kind_of(text) when is_binary(text) do
    Enum.find_value(@kinds, fn {value, _word} -> if Atom.to_string(value) == text, do: value end)
  end

  def kind_of(_text), do: nil

  @doc """
  A local date and time in words, in the form of the locale of the page
  (ADR 0075): `16 November 2026, 8:30 am`.
  """
  def time(%DateTime{} = local), do: RescordWeb.Locale.date_time(local)

  @doc """
  The size of a file in words, in units of 1000 bytes.

      iex> RescordWeb.JournalWords.file_size(812)
      "812 bytes"

      iex> RescordWeb.JournalWords.file_size(2_450_000)
      "2.5 MB"
  """
  def file_size(bytes) when bytes < 1000, do: "#{bytes} bytes"
  def file_size(bytes) when bytes < 1_000_000, do: "#{round(bytes / 1000)} kB"
  def file_size(bytes), do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  @doc """
  The state of a condition of a resident (ADR 0083), as the kind of a
  `<.state>` and its word. A chronic condition says so while it is ongoing.
  """
  def condition_state(%{ended_on: %Date{}}), do: {"ok", "Resolved"}
  def condition_state(%{chronic: true}), do: {"info", "Chronic"}
  def condition_state(_ongoing), do: {"info", "Ongoing"}

  @doc """
  The days of a condition of a resident in words, with how long it is:
  `Since 3 November 2026, 25 days` and `24 September 2026 to 2 October
  2026, 9 days`. A resolved condition counts its first day and its last day.
  """
  def condition_days(%{started_on: from, ended_on: nil}, today) do
    case Date.diff(today, from) do
      0 -> "Since today"
      days -> "Since #{ResidentWords.date(from)}, #{count(days, "day")}"
    end
  end

  def condition_days(%{started_on: from, ended_on: to}, _today) do
    "#{ResidentWords.date(from)} to #{ResidentWords.date(to)}, " <>
      count(Date.diff(to, from) + 1, "day")
  end

  @doc """
  A condition of a resident as the choice of a form: `Bumblefoot, since 3
  November 2026`. The episode has its condition with the label.
  """
  def condition_choice(%{ended_on: nil} = episode),
    do: "#{episode.condition.label}, since #{ResidentWords.date(episode.started_on)}"

  def condition_choice(episode) do
    "#{episode.condition.label}, #{ResidentWords.date(episode.started_on)} to " <>
      ResidentWords.date(episode.ended_on)
  end

  @doc "A number of things in words: `1 entry`, `4 entries`, `1,095 days`."
  def count(1, "entry"), do: "1 entry"
  def count(number, "entry"), do: "#{number(number)} entries"
  def count(1, thing), do: "1 #{thing}"
  def count(number, thing), do: "#{number(number)} #{thing}s"

  @doc "A month in words, from a day of it (ADR 0075): `November 2026`."
  def month(%Date{} = day), do: RescordWeb.Locale.month(day)

  @doc "The facts of an entry in one line, or `nil` for an entry with words only."
  def facts(%{measurement: %{} = measurement}) do
    unit = if measurement.unit, do: " #{measurement.unit.label}", else: ""
    "#{measurement.measure_kind.label}: #{number(measurement.value)}#{unit}"
  end

  def facts(%{diagnosis: %{} = diagnosis}), do: "Condition: #{diagnosis.condition.label}"
  def facts(%{procedure: %{} = procedure}), do: "Procedure: #{procedure.procedure_kind.label}"
  def facts(%{vaccination: %{} = vaccination}), do: "Vaccine: #{vaccination.vaccine}"

  def facts(%{prescription: %{} = prescription}) do
    [
      prescription.medication,
      prescription.dose,
      prescription.route && route(prescription.route),
      days(prescription.starts_on, prescription.ends_on)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  def facts(%{dose: %{} = dose}) do
    of = if match?(%{medication: _}, dose.prescription), do: dose.prescription.medication
    [of, dose.amount] |> Enum.reject(&is_nil/1) |> Enum.join(": ") |> nil_if_empty()
  end

  def facts(_entry), do: nil

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(text), do: text

  defp days(nil, nil), do: nil
  defp days(from, nil), do: "from #{ResidentWords.date(from)}"
  defp days(nil, to), do: "to #{ResidentWords.date(to)}"
  defp days(from, to), do: "#{ResidentWords.date(from)} to #{ResidentWords.date(to)}"

  @doc """
  A number with the marks of the locale of the page (ADR 0075), each digit
  of it, and no zeros after the point: `1,095`. It never rounds.
  """
  def number(%Decimal{} = value), do: RescordWeb.Locale.number(value)
  def number(value) when is_integer(value), do: RescordWeb.Locale.number(value)
end
