defmodule RescordWeb.TransferWords do
  @moduledoc """
  The words of the partnerships and the transfers (ADR 0042): the state of
  each, the parts of a copy, and the facts of a copy, which is plain data
  with text keys (`Rescord.Transfers.Snapshot`).
  """

  alias RescordWeb.{JournalWords, ResidentWords}

  @parts [
    journal: "The other journal entries",
    stay: "The stay: the arrival, an absence and the departure",
    placements: "The placements",
    relations: "The families, the groups, the parents and the young",
    photos: "The photos, the albums and the profile picture"
  ]

  @doc "The parts that a sender can add, each with its words, in order."
  def parts, do: @parts

  @doc "The words of a part."
  def part(key), do: Keyword.fetch!(@parts, key)

  @doc "The part with the text of a field of a form, or `:error`. It makes no atom."
  def part_of(text) when is_binary(text) do
    case Enum.find(@parts, fn {key, _words} -> Atom.to_string(key) == text end) do
      {key, _words} -> {:ok, key}
      nil -> :error
    end
  end

  def part_of(_other), do: :error

  @doc """
  How far the files of a transfer that is sending got, such as
  `"120 of 300 files"` (ADR 0100).

      iex> RescordWeb.TransferWords.files_copied(%{files_copied: 1, files_total: 3})
      "1 of 3 files"
      iex> RescordWeb.TransferWords.files_copied(%{files_copied: 0, files_total: 1})
      "0 of 1 file"
  """
  def files_copied(%{files_copied: copied, files_total: 1}), do: "#{copied} of 1 file"
  def files_copied(%{files_copied: copied, files_total: total}), do: "#{copied} of #{total} files"

  @doc """
  Why the files of a transfer did not arrive, in words for the refuge that
  sent it (ADR 0100).
  """
  def failure(:file_missing),
    do:
      "A photo or a file of the resident is gone from this organisation. " <>
        "Send it again when the file is back, or withdraw it and send the resident again."

  def failure(:interrupted),
    do:
      "Rescord stopped while it sent the files, and did not start again. " <>
        "Send it again, or withdraw it."

  def failure(:store_refused),
    do:
      "Rescord could not reach the files, and stopped trying. " <>
        "Send it again, or withdraw it."

  def failure(_other), do: "The files did not arrive."

  @doc "The state of a partnership or a transfer, in words, and its kind for a badge."
  def state(:asked), do: {"Asked", "info"}
  def state(:accepted), do: {"Accepted", "ok"}
  def state(:declined), do: {"Declined", "none"}
  def state(:ended), do: {"Ended", "none"}
  def state(:sending), do: {"Sending", "info"}
  def state(:failed), do: {"Not sent", "alert"}
  def state(:sent), do: {"Waits for an answer", "info"}
  def state(:withdrawn), do: {"Withdrawn", "none"}
  def state(:exported), do: {"Exported to a file", "ok"}
  def state(:active), do: {"Active", "ok"}

  @doc "A date of a copy, in words, or `nil`."
  def date(nil), do: nil

  def date(text) when is_binary(text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> ResidentWords.date(date)
      _bad -> nil
    end
  end

  def date(_other), do: nil

  @doc "An instant of a copy, in words, in the time zone `zone`."
  def time(text, zone) when is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, instant, _offset} ->
        instant |> DateTime.shift_zone!(zone, Tz.TimeZoneDatabase) |> JournalWords.time()

      _bad ->
        nil
    end
  end

  def time(_text, _zone), do: nil

  @doc "A value of a copy that is a key of Rescord, such as `in_care`, in words."
  def value(nil), do: nil

  def value(text) when is_binary(text),
    do: text |> String.replace("_", " ") |> String.capitalize()

  def value(_other), do: nil

  @doc "The facts of an entry of a copy, in one line, or `nil`."
  def facts(%{"kind" => "measurement", "facts" => f}) do
    unit = if f["unit"], do: " #{f["unit"]}", else: ""
    "#{f["measure_kind"]}: #{f["value"]}#{unit}"
  end

  def facts(%{"kind" => "diagnosis", "facts" => f}), do: "Condition: #{f["condition"]}"
  def facts(%{"kind" => "procedure", "facts" => f}), do: "Procedure: #{f["procedure"]}"
  def facts(%{"kind" => "vaccination", "facts" => f}), do: "Vaccine: #{f["vaccine"]}"

  def facts(%{"kind" => "prescription", "facts" => f}) do
    [f["medication"], f["dose"], value(f["route"]), days(f["starts_on"], f["ends_on"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  def facts(%{"kind" => "dose", "facts" => f}) do
    case Enum.reject([f["medication"], f["amount"]], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, ": ")
    end
  end

  def facts(_entry), do: nil

  @doc """
  The state of a condition of a copy, as the kind of a state and its word:
  resolved with a last day, and else chronic or ongoing.
  """
  def condition_state(%{"ended_on" => day}) when is_binary(day), do: {"ok", "Resolved"}
  def condition_state(%{"chronic" => true}), do: {"info", "Chronic"}
  def condition_state(_ongoing), do: {"info", "Ongoing"}

  @doc """
  The days and the note of a condition of a copy, in one line:
  `Since 3 November 2026 · left hind foot`.
  """
  def condition(%{} = condition) do
    days =
      case {date(condition["started_on"]), date(condition["ended_on"])} do
        {nil, _to} -> nil
        {from, nil} -> "Since #{from}"
        {from, to} -> "#{from} to #{to}"
      end

    [days, condition["note"]]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp days(nil, nil), do: nil
  defp days(from, nil), do: "from #{date(from)}"
  defp days(nil, to), do: "to #{date(to)}"
  defp days(from, to), do: "#{date(from)} to #{date(to)}"
end
