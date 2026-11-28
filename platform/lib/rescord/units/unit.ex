defmodule Rescord.Units.Unit do
  @moduledoc """
  One unit of measure that Rescord knows (ADR 0071): a unit of the
  catalogue of `Rescord.Units`, such as `kg`, or a ratio of two of them,
  such as `mg/kg`.

  Make a unit with `Rescord.Units.parse/1` or `Rescord.Units.ratio/2`, and
  never by hand: two units that mean the same thing are then equal with
  `==`.

    * `code` - the text that names the unit in the database and in a form,
      which is its symbol: `"kg"`, `"mg/kg"`.
    * `symbol` - what a page shows after the number.
    * `name` - the unit in words: `"kilogram"`, `"milligram per kilogram"`.
    * `key` - the name of the unit as CLDR writes it, where CLDR has the
      unit: `:kilogram`, `:milliliter`. A ratio has the pair of its two
      keys.
    * `dimension` - what the unit measures: `:mass`, or the pair
      `{:mass, :mass}` for a ratio. Two units convert only inside one
      dimension.
    * `numerator` and `denominator` - the two units of a ratio, and `nil`
      for a unit of the catalogue.
    * `scale` and `offset` - the conversion to the base unit of the
      dimension, for `Rescord.Units` alone.
  """

  @enforce_keys [:code, :symbol, :name, :key, :dimension, :scale, :offset]
  defstruct [
    :code,
    :symbol,
    :name,
    :key,
    :dimension,
    :scale,
    :offset,
    numerator: nil,
    denominator: nil
  ]

  @typedoc "What a unit measures. A ratio has the dimensions of its two units."
  @type dimension :: atom | {atom, atom}

  @type t :: %__MODULE__{
          code: String.t(),
          symbol: String.t(),
          name: String.t(),
          key: atom | {atom, atom},
          dimension: dimension,
          scale: {Decimal.t(), Decimal.t()},
          offset: Decimal.t(),
          numerator: t | nil,
          denominator: t | nil
        }

  @doc "Whether the unit is a ratio of two units, such as `mg/kg`."
  @spec ratio?(t) :: boolean
  def ratio?(%__MODULE__{numerator: nil}), do: false
  def ratio?(%__MODULE__{}), do: true

  defimpl String.Chars do
    def to_string(unit), do: unit.code
  end

  defimpl Jason.Encoder do
    def encode(unit, opts), do: Jason.Encode.string(unit.code, opts)
  end
end
