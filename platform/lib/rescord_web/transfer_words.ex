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

  @doc "The state of a partnership or a transfer, in words, and its kind for a badge."
  def state(:asked), do: {"Asked", "info"}
  def state(:accepted), do: {"Accepted", "ok"}
  def state(:declined), do: {"Declined", "none"}
  def state(:ended), do: {"Ended", "none"}
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

  defp days(nil, nil), do: nil
  defp days(from, nil), do: "from #{date(from)}"
  defp days(nil, to), do: "to #{date(to)}"
  defp days(from, to), do: "#{date(from)} to #{date(to)}"
end
