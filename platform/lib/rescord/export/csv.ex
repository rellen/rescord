defmodule Rescord.Export.CSV do
  @moduledoc """
  The CSV of a table of the export (ADR 0054), as RFC 4180 writes it: commas,
  a header row, CRLF at the end of each row, and quotes round a cell that
  holds a comma, a quote or a line break, with each quote in it doubled.

  The file starts with the byte order mark of UTF-8, so that a spreadsheet
  reads the names with accents and other scripts correctly.

  A text that starts with `=`, `+`, `-`, `@`, a tab or a carriage return gets
  a `'` before it, so that a spreadsheet shows it and does not run it as a
  formula. Only a text gets it: a number, such as a quantity of `-5`, keeps
  its sign.

  A value becomes text in this way:

    * nothing is an empty cell;
    * a date, a time and an instant are in ISO 8601, an instant in UTC;
    * a list is its values, each made text, with `; ` between them;
    * a map is JSON.
  """

  @bom "﻿"
  @formula_starts ["=", "+", "-", "@", "\t", "\r"]

  @doc """
  The CSV of a header and rows, as iodata.

      iex> Rescord.Export.CSV.encode(["name", "note"], [["Biscuit", "shy, quiet"]])
      ...> |> IO.iodata_to_binary()
      "﻿name,note\\r\\nBiscuit,\\"shy, quiet\\"\\r\\n"
  """
  @spec encode([String.t()], [[term]]) :: iodata
  def encode(header, rows) do
    [@bom, row(header) | Enum.map(rows, &row/1)]
  end

  defp row(cells), do: [Enum.map_intersperse(cells, ",", &cell/1), "\r\n"]

  @doc """
  One cell: the value as text, with quotes when the text needs them.

      iex> Rescord.Export.CSV.cell(~s(say "hi"))
      ~s("say ""hi\""")

      iex> Rescord.Export.CSV.cell("=1+1")
      "'=1+1"

      iex> Rescord.Export.CSV.cell(Decimal.new("-5"))
      "-5"
  """
  @spec cell(term) :: String.t()
  def cell(value) do
    text = text(value)

    if String.contains?(text, [",", "\"", "\r", "\n"]),
      do: "\"" <> String.replace(text, "\"", "\"\"") <> "\"",
      else: text
  end

  defp text(nil), do: ""
  defp text(value) when is_boolean(value), do: Atom.to_string(value)
  defp text(value) when is_atom(value), do: Atom.to_string(value)
  defp text(value) when is_binary(value), do: safe(value)
  defp text(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp text(%Decimal{} = value), do: Decimal.to_string(value, :normal)

  defp text(%DateTime{} = value),
    do: value |> DateTime.shift_zone!("Etc/UTC", Tz.TimeZoneDatabase) |> DateTime.to_iso8601()

  defp text(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp text(%Date{} = value), do: Date.to_iso8601(value)
  defp text(%Time{} = value), do: Time.to_iso8601(value)
  defp text(%Ash.CiString{} = value), do: value |> to_string() |> safe()
  defp text(values) when is_list(values), do: Enum.map_join(values, "; ", &text/1)
  defp text(value) when is_map(value), do: value |> plain() |> Jason.encode!() |> safe()
  defp text(value), do: safe(inspect(value))

  # A struct as a plain map for JSON: no field of Ash or Ecto, such as
  # `__meta__`, and no value that was not loaded.
  defp plain(%module{} = value) when module in [DateTime, NaiveDateTime, Date, Time, Decimal],
    do: value

  defp plain(%{__struct__: _} = value), do: value |> Map.from_struct() |> plain()

  defp plain(value) when is_map(value) do
    for {key, field} <- value,
        not String.starts_with?(to_string(key), "__"),
        not match?(%Ash.NotLoaded{}, field),
        into: %{},
        do: {key, plain(field)}
  end

  defp plain(values) when is_list(values), do: Enum.map(values, &plain/1)
  defp plain(value), do: value

  defp safe(text) do
    if String.starts_with?(text, @formula_starts), do: "'" <> text, else: text
  end
end
