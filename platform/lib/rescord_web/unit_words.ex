defmodule RescordWeb.UnitWords do
  @moduledoc """
  The words that a page uses for a quantity and for a unit of measure
  (ADR 0071). A page never shows the atom of a dimension.

  `quantity/1` is the one place that writes a `Rescord.Units.Quantity` for a
  person: the number, and then the symbol of the unit. The symbol is the
  same in each language. The number is the work of
  `RescordWeb.JournalWords.number/1`, as for each other number of a page,
  and it keeps each digit: this function never rounds. A page that wants
  fewer digits rounds the quantity first, and says so.
  """

  alias Rescord.Units
  alias Rescord.Units.{Quantity, Unit}
  alias RescordWeb.JournalWords

  @dimensions [
    mass: "a mass",
    volume: "a volume",
    length: "a length",
    temperature: "a temperature",
    time: "a time",
    energy: "an energy",
    tablet: "a count",
    capsule: "a count",
    drop: "a count",
    international_unit: "an amount that converts to no other unit"
  ]

  @doc """
  A quantity for a person: `1,095 g`, `5 mg/kg`, `38.5 °C`, `2 tablets`.

      iex> {:ok, quantity} = Rescord.Units.Quantity.parse("1095 g")
      iex> RescordWeb.UnitWords.quantity(quantity)
      "1,095 g"

      iex> {:ok, quantity} = Rescord.Units.Quantity.parse("1.5 tablet")
      iex> RescordWeb.UnitWords.quantity(quantity)
      "1.5 tablets"
  """
  @spec quantity(Quantity.t()) :: String.t()
  def quantity(%Quantity{value: value, unit: unit}),
    do: "#{JournalWords.number(value)} #{symbol(unit, value)}"

  @doc "The words for a dimension of the catalogue: `a mass`."
  @spec dimension(atom) :: String.t()
  def dimension(dimension), do: Keyword.fetch!(@dimensions, dimension)

  @doc """
  What a unit is, for a person who keeps the list of units: `kilogram, a
  mass`, or `milligram per kilogram` for a ratio.

      iex> {:ok, unit} = Rescord.Units.parse("kg")
      iex> RescordWeb.UnitWords.meaning(unit)
      "kilogram, a mass"
  """
  @spec meaning(Unit.t()) :: String.t()
  def meaning(%Unit{numerator: nil} = unit), do: "#{unit.name}, #{dimension(unit.dimension)}"
  def meaning(%Unit{} = unit), do: unit.name

  # A count is a word, so it has a plural: `1 tablet`, `2 tablets`. Each
  # other symbol stays as it is.
  defp symbol(%Unit{numerator: nil} = unit, value) do
    if Units.count?(unit) and not Decimal.equal?(value, 1) do
      unit.symbol <> "s"
    else
      unit.symbol
    end
  end

  defp symbol(%Unit{} = unit, _value), do: unit.symbol
end
