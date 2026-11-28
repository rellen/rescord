defmodule Rescord.Log.Shape do
  @moduledoc """
  A value of a crash report that `Rescord.Log.Translator` replaced with its
  shape. Elixir writes such a value with `inspect/2`, and this struct then
  reads as the text of the shape, with no quotes.
  """

  @enforce_keys [:text]
  defstruct [:text]

  @type t :: %__MODULE__{text: String.t()}

  @doc "The shape of `value`, as `Shoddy.Terms.shape/2` gives it."
  @spec of(term) :: t
  def of(value), do: %__MODULE__{text: Shoddy.Terms.shape(value)}

  defimpl Inspect do
    def inspect(%{text: text}, _opts), do: text
  end
end
