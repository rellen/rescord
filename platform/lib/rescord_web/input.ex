defmodule RescordWeb.Input do
  @moduledoc """
  What a page reads from the fields of a form that the browser sends.

  Each LiveView imports `text/1` (`use RescordWeb, :live_view`). The browser
  can send any value, so a value that is not text gives `nil`.
  """

  @doc """
  The text of a field, or `nil` for a field that is empty, has only
  whitespace, or is not text. The text keeps its whitespace: the action
  decides what to do with it.

      iex> RescordWeb.Input.text("Biscuit")
      "Biscuit"

      iex> Enum.map(["", "  ", nil, ["a list"]], &RescordWeb.Input.text/1)
      [nil, nil, nil, nil]
  """
  @spec text(term) :: String.t() | nil
  def text(value) when is_binary(value),
    do: if(Shoddy.Strings.blank?(value), do: nil, else: value)

  def text(_other), do: nil
end
