defmodule Rescord.Units.Quantity do
  @moduledoc """
  A number with its unit: `1,095 g`, `5 mg/kg`, `0.2 mL` (ADR 0071).

  The number is a `Decimal`, and the unit is a `Rescord.Units.Unit`. A
  quantity keeps the unit that a person wrote: Rescord converts when a page
  or a calculation asks, and not when it stores.

  `Rescord.Units` has the arithmetic: `multiply/2`, `divide/2`, `add/2` and
  `subtract/2`.

      iex> alias Rescord.Units.Quantity
      iex> {:ok, weight} = Quantity.parse("1095 g")
      iex> {:ok, in_kilograms} = Quantity.convert(weight, "kg")
      iex> to_string(in_kilograms)
      "1.095 kg"
  """

  alias Rescord.Units
  alias Rescord.Units.Unit

  @enforce_keys [:value, :unit]
  defstruct [:value, :unit]

  @type t :: %__MODULE__{value: Decimal.t(), unit: Unit.t()}

  # A number as a person writes it, with a point and no comma: a comma is
  # the mark of a thousand in one country and of a decimal in another.
  # The sigils are in functions: a module attribute cannot hold a compiled
  # expression.
  defp whole_number, do: ~r/^[+-]?(?:\d+(?:\.\d+)?|\.\d+)$/
  defp number_and_unit, do: ~r/^([+-]?(?:\d+(?:\.\d+)?|\.\d+))\s*([^\s\d.,].*)$/u

  @doc """
  A quantity from a number and a unit. The number is a `Decimal`, a whole
  number, or a text such as `"0.2"`. A float is refused: it is not exact.

      iex> {:ok, quantity} = Rescord.Units.Quantity.new("0.2", "ml")
      iex> to_string(quantity)
      "0.2 mL"

      iex> Rescord.Units.Quantity.new(0.2, "mL")
      {:error, :not_a_number}

      iex> Rescord.Units.Quantity.new(1, "scoop")
      {:error, :unknown_unit}
  """
  @spec new(term, term) :: {:ok, t} | {:error, :not_a_number | :unknown_unit}
  def new(value, unit) do
    with {:ok, value} <- number(value) do
      case Units.parse(unit) do
        {:ok, unit} -> {:ok, %__MODULE__{value: value, unit: unit}}
        :error -> {:error, :unknown_unit}
      end
    end
  end

  @doc """
  A quantity from a text: a number and then a unit, `12.5 kg` or `5mg/kg`.

      iex> {:ok, quantity} = Rescord.Units.Quantity.parse(" 2 tablets ")
      iex> {Decimal.to_string(quantity.value), quantity.unit.symbol}
      {"2", "tablet"}

      iex> Rescord.Units.Quantity.parse("1,5 kg")
      {:error, :not_a_number}

      iex> Rescord.Units.Quantity.parse("12.5")
      {:error, :unknown_unit}
  """
  @spec parse(term) :: {:ok, t} | {:error, :not_a_number | :unknown_unit}
  def parse(text) when is_binary(text) do
    trimmed = if String.valid?(text), do: String.trim(text), else: ""

    cond do
      captures = Regex.run(number_and_unit(), trimmed) ->
        [_all, value, unit] = captures
        new(value, unit)

      Regex.match?(whole_number(), trimmed) ->
        {:error, :unknown_unit}

      true ->
        {:error, :not_a_number}
    end
  end

  def parse(_other), do: {:error, :not_a_number}

  @doc "The quantity in another unit of the same dimension."
  @spec convert(t, Units.unit()) ::
          {:ok, t} | {:error, :unknown_unit | :not_the_same_dimension | :not_a_number}
  def convert(%__MODULE__{} = quantity, to) do
    with {:ok, unit} <- known(to),
         {:ok, value} <- Units.convert(quantity.value, quantity.unit, unit) do
      {:ok, %__MODULE__{value: value, unit: unit}}
    end
  end

  @doc """
  The quantity with its number rounded to a number of places after the
  point, half up unless `mode` says another way of `Decimal.round/3`.

      iex> {:ok, quantity} = Rescord.Units.Quantity.parse("1.2345 mL")
      iex> to_string(Rescord.Units.Quantity.round(quantity, 2))
      "1.23 mL"
  """
  @spec round(t, integer, atom) :: t
  def round(%__MODULE__{} = quantity, places \\ 2, mode \\ :half_up),
    do: %__MODULE__{quantity | value: Decimal.round(quantity.value, places, mode)}

  @doc "The quantity times a plain number: three doses of `0.2 mL`."
  @spec times(t, Decimal.t() | integer) :: t
  def times(%__MODULE__{} = quantity, %Decimal{} = number),
    do: %__MODULE__{quantity | value: Decimal.mult(quantity.value, number)}

  def times(%__MODULE__{} = quantity, number) when is_integer(number),
    do: times(quantity, Decimal.new(number))

  @doc """
  Compares two quantities of one dimension: `{:ok, :lt}`, `{:ok, :eq}` or
  `{:ok, :gt}`.

      iex> alias Rescord.Units.Quantity
      iex> {:ok, one} = Quantity.parse("900 g")
      iex> {:ok, other} = Quantity.parse("1 kg")
      iex> Quantity.compare(one, other)
      {:ok, :lt}
  """
  @spec compare(t, t) :: {:ok, :lt | :eq | :gt} | {:error, :not_the_same_dimension}
  def compare(%__MODULE__{} = one, %__MODULE__{} = other) do
    case Units.convert(other.value, other.unit, one.unit) do
      {:ok, value} -> {:ok, Decimal.compare(one.value, value)}
      {:error, _reason} -> {:error, :not_the_same_dimension}
    end
  end

  @doc """
  Whether two quantities are the same number of the same unit: `1.0 kg` is
  `1 kg`, and is not `1000 g`. `compare/2` asks about the amount.
  """
  @spec equal?(t, t) :: boolean
  def equal?(%__MODULE__{unit: unit} = one, %__MODULE__{unit: unit} = other),
    do: Decimal.equal?(one.value, other.value)

  def equal?(%__MODULE__{}, %__MODULE__{}), do: false

  @doc "Whether the number is more than zero."
  @spec positive?(t) :: boolean
  def positive?(%__MODULE__{value: value}), do: Decimal.positive?(value)

  @doc "The number as a text with no exponent and no zeros at the end: `1095`, `0.2`."
  @spec plain(t) :: String.t()
  def plain(%__MODULE__{value: value}),
    do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp number(%Decimal{coef: coef} = value) when is_integer(coef), do: {:ok, value}
  defp number(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp number(text) when is_binary(text) do
    trimmed = if String.valid?(text), do: String.trim(text), else: ""

    if Regex.match?(whole_number(), trimmed) do
      {:ok, Decimal.new(trimmed)}
    else
      {:error, :not_a_number}
    end
  end

  defp number(_other), do: {:error, :not_a_number}

  defp known(unit) do
    case Units.parse(unit) do
      {:ok, unit} -> {:ok, unit}
      :error -> {:error, :unknown_unit}
    end
  end

  defimpl String.Chars do
    def to_string(quantity),
      do: "#{Rescord.Units.Quantity.plain(quantity)} #{quantity.unit.symbol}"
  end

  defimpl Jason.Encoder do
    def encode(quantity, opts) do
      Jason.Encode.map(
        %{"value" => Rescord.Units.Quantity.plain(quantity), "unit" => quantity.unit.code},
        opts
      )
    end
  end
end
