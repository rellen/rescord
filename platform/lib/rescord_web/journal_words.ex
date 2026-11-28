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
end
