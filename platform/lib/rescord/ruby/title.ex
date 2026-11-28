defmodule Rescord.Ruby.Title do
  @moduledoc """
  The title of a conversation: the first words of its first message, on
  one line, cut at the end of a word.
  """

  @most 60

  @doc "The title for a conversation that starts with `text`, or `nil` for a text with no word."
  @spec of(String.t()) :: String.t() | nil
  def of(text) when is_binary(text) do
    case text |> String.split() |> Enum.join(" ") do
      "" -> nil
      line -> if String.length(line) <= @most, do: line, else: cut(line) <> "…"
    end
  end

  # The whole words that fit. A first word that is too long is cut where
  # it is.
  defp cut(line) do
    {kept, _size} =
      line
      |> String.split(" ")
      |> Enum.reduce_while({[], 0}, fn word, {kept, size} ->
        size = size + String.length(word) + if(kept == [], do: 0, else: 1)
        if size <= @most, do: {:cont, {[word | kept], size}}, else: {:halt, {kept, size}}
      end)

    case kept do
      [] -> String.slice(line, 0, @most)
      words -> words |> Enum.reverse() |> Enum.join(" ")
    end
  end
end
