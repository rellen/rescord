defmodule Rescord.Units do
  @moduledoc """
  The units of measure that Rescord knows, and the arithmetic on quantities
  that have a unit (ADR 0071).

  The catalogue is in this module, and not in the database. It holds what a
  refuge measures and doses with: a mass, a volume, a length, a temperature,
  a time, an energy, the counts of a medication (a tablet, a capsule, a
  drop) and the international unit. Each unit has an exact factor to the
  base unit of its dimension.

  A **ratio** is one unit for each of another: `mg/kg`, `mg/mL`,
  `mg/tablet`, `mL/h`. A ratio never cancels. `mg/kg` is a mass of a
  medication for each mass of a body, and it is not a plain number.

  ## Rules

    * Each number is a `Decimal`. No function takes or returns a float.
    * A result is exact, or has 28 significant digits when a division does
      not end. A caller rounds for a page, with
      `Rescord.Units.Quantity.round/2`.
    * No function raises for a text that a person typed: it returns
      `:error` or `{:error, reason}`.

  ## Examples

      iex> {:ok, kilograms} = Rescord.Units.convert(Decimal.new("1095"), "g", "kg")
      iex> Decimal.to_string(kilograms)
      "1.095"

      iex> Rescord.Units.dimension("mg/kg")
      {:mass, :mass}

      iex> Rescord.Units.convert(Decimal.new(1), "kg", "mL")
      {:error, :not_the_same_dimension}

      iex> alias Rescord.Units.Quantity
      iex> {:ok, weight} = Quantity.parse("12.5 kg")
      iex> {:ok, rate} = Quantity.parse("5 mg/kg")
      iex> {:ok, strength} = Quantity.parse("50 mg/mL")
      iex> {:ok, dose} = Rescord.Units.multiply(rate, weight)
      iex> to_string(dose)
      "62.5 mg"
      iex> {:ok, volume} = Rescord.Units.divide(dose, strength)
      iex> to_string(volume)
      "1.25 mL"
  """

  alias Rescord.Units.{Quantity, Unit}

  # The catalogue: the key, the symbol, the name, the dimension, the factor
  # to the base unit of the dimension, and the other spellings that
  # `parse/1` reads. A factor is a text, so that it is exact, or a pair
  # `{multiply, divide}` with an offset to take away first.
  #
  # The symbol of a microgram is `mcg`. `parse/1` reads `µg`, and Rescord
  # never writes it: a person can read the `µ` as an `m`, which is a dose
  # 1,000 times too large.
  #
  # Not here on purpose: a teaspoon, a cup and a fluid ounce, which differ
  # between countries, and a percent, which can mean three things.
  @catalogue [
    # A mass. The base unit is the kilogram.
    {:microgram, "mcg", "microgram", :mass, "0.000000001", ~w(µg μg ug micrograms)},
    {:milligram, "mg", "milligram", :mass, "0.000001", ~w(milligrams)},
    {:gram, "g", "gram", :mass, "0.001", ~w(gm grams)},
    {:kilogram, "kg", "kilogram", :mass, "1", ~w(kgs kilo kilos kilograms)},
    {:ounce, "oz", "ounce", :mass, "0.028349523125", ~w(ounces)},
    {:pound, "lb", "pound", :mass, "0.45359237", ~w(lbs pounds)},
    # A volume. The base unit is the litre.
    {:milliliter, "mL", "millilitre", :volume, "0.001",
     ~w(cc millilitres milliliter milliliters)},
    {:liter, "L", "litre", :volume, "1", ~w(litres liter liters)},
    # A length. The base unit is the metre.
    {:millimeter, "mm", "millimetre", :length, "0.001", ~w(millimetres millimeter millimeters)},
    {:centimeter, "cm", "centimetre", :length, "0.01", ~w(centimetres centimeter centimeters)},
    {:meter, "m", "metre", :length, "1", ~w(metres meter meters)},
    {:inch, "in", "inch", :length, "0.0254", ~w(inches)},
    # A temperature. The base unit is the degree Celsius.
    {:celsius, "°C", "degree Celsius", :temperature, "1",
     ["℃", "degC", "deg C", "celsius", "degrees Celsius"]},
    {:fahrenheit, "°F", "degree Fahrenheit", :temperature, {{5, 9}, 32},
     ["℉", "degF", "deg F", "fahrenheit", "degrees Fahrenheit"]},
    # A time. The base unit is the second.
    {:second, "s", "second", :time, "1", ~w(sec secs seconds)},
    {:minute, "min", "minute", :time, "60", ~w(mins minutes)},
    {:hour, "h", "hour", :time, "3600", ~w(hr hrs hours)},
    {:day, "d", "day", :time, "86400", ~w(days)},
    # An energy. The base unit is the kilojoule.
    {:kilojoule, "kJ", "kilojoule", :energy, "1", ~w(kilojoules)},
    {:kilocalorie, "kcal", "kilocalorie", :energy, "4.184", ~w(kilocalories)},
    # A count is a dimension of its own, and converts to nothing.
    {:tablet, "tablet", "tablet", :tablet, "1", ~w(tab tabs tablets)},
    {:capsule, "capsule", "capsule", :capsule, "1", ~w(cap caps capsules)},
    {:drop, "drop", "drop", :drop, "1", ~w(drops gtt)},
    # An international unit has no mass: its size depends on the substance.
    {:international_unit, "IU", "international unit", :international_unit, "1",
     ["international units"]}
  ]

  @counts [:tablet, :capsule, :drop]

  @units (for {key, symbol, name, dimension, factor, _spellings} <- @catalogue do
            {scale, offset} =
              case factor do
                {{multiply, divide}, offset} ->
                  {{Decimal.new(multiply), Decimal.new(divide)}, Decimal.new(offset)}

                text when is_binary(text) ->
                  {{Decimal.new(text), Decimal.new(1)}, Decimal.new(0)}
              end

            %Unit{
              code: symbol,
              symbol: symbol,
              name: name,
              key: key,
              dimension: dimension,
              scale: scale,
              offset: offset
            }
          end)

  @spellings (for {key, symbol, name, _dimension, _factor, spellings} <- @catalogue,
                  spelling <- [symbol, name | spellings] do
                {spelling, key}
              end)

  # A spelling names one unit, with and without regard to the case. The
  # compiler stops for a catalogue that breaks this.
  for {_folded, keys} <-
        Enum.group_by(@spellings, fn {spelling, _key} -> String.downcase(spelling) end, fn
          {_spelling, key} -> key
        end),
      length(Enum.uniq(keys)) > 1 do
    raise CompileError,
      description: "the units #{inspect(Enum.uniq(keys))} share a spelling"
  end

  @by_key Map.new(@units, &{&1.key, &1})
  @exact Map.new(@spellings, fn {spelling, key} -> {spelling, Map.fetch!(@by_key, key)} end)
  @folded Map.new(@spellings, fn {spelling, key} ->
            {String.downcase(spelling), Map.fetch!(@by_key, key)}
          end)

  @dimensions Enum.uniq(Enum.map(@units, & &1.dimension))

  # The precision of each calculation, whatever the process set before.
  @context %Decimal.Context{precision: 28, rounding: :half_even}

  @typedoc "A unit, or the text that names one."
  @type unit :: Unit.t() | String.t()

  @doc "Each unit of the catalogue, in its order: by dimension, and small to large."
  @spec all() :: [Unit.t()]
  def all, do: @units

  @doc "The dimensions of the catalogue: `:mass`, `:volume`, and so on."
  @spec dimensions() :: [atom]
  def dimensions, do: @dimensions

  @doc """
  The units of a dimension, in the order of the catalogue, for a select.
  A pair of dimensions gives each ratio of the two.

      iex> Enum.map(Rescord.Units.units_of(:mass), & &1.symbol)
      ["mcg", "mg", "g", "kg", "oz", "lb"]

      iex> Enum.map(Rescord.Units.units_of({:mass, :volume}), & &1.symbol) |> Enum.take(3)
      ["mcg/mL", "mcg/L", "mg/mL"]
  """
  @spec units_of(Unit.dimension()) :: [Unit.t()]
  def units_of({over, under}) do
    for numerator <- units_of(over),
        denominator <- units_of(under),
        {:ok, unit} <- [ratio(numerator, denominator)],
        do: unit
  end

  def units_of(dimension), do: Enum.filter(@units, &(&1.dimension == dimension))

  @doc """
  The unit that a text names, or `:error`. The text is a symbol (`kg`), a
  name (`kilogram`, `Kilograms`), or a ratio of two (`mg/kg`,
  `mg per kg`). The symbol as it is comes first, and then the spelling with
  no regard to the case: `ML` is a millilitre.

      iex> {:ok, unit} = Rescord.Units.parse("Milligrams / kg")
      iex> unit.symbol
      "mg/kg"

      iex> {:ok, unit} = Rescord.Units.parse("µg")
      iex> unit.symbol
      "mcg"

      iex> Rescord.Units.parse("bag")
      :error
  """
  @spec parse(term) :: {:ok, Unit.t()} | :error
  def parse(%Unit{} = unit), do: {:ok, unit}

  def parse(text) when is_binary(text) do
    if String.valid?(text) do
      case Regex.split(~r{\s*/\s*|\s+per\s+}iu, tidy(text)) do
        [one] ->
          simple(one)

        [over, under] ->
          with {:ok, numerator} <- simple(over),
               {:ok, denominator} <- simple(under) do
            ratio(numerator, denominator)
          end

        _more ->
          :error
      end
    else
      :error
    end
  end

  def parse(_other), do: :error

  @doc """
  The ratio of two units of the catalogue, or `:error`. A temperature and
  a ratio cannot be a part of a ratio.
  """
  @spec ratio(Unit.t(), Unit.t()) :: {:ok, Unit.t()} | :error
  def ratio(
        %Unit{numerator: nil, dimension: over} = numerator,
        %Unit{numerator: nil, dimension: under} = denominator
      )
      when over != :temperature and under != :temperature do
    {multiply, divide} = numerator.scale
    {under_multiply, under_divide} = denominator.scale

    {:ok,
     %Unit{
       code: "#{numerator.code}/#{denominator.code}",
       symbol: "#{numerator.symbol}/#{denominator.symbol}",
       name: "#{numerator.name} per #{denominator.name}",
       key: {numerator.key, denominator.key},
       dimension: {over, under},
       scale:
         exactly(fn ->
           {Decimal.mult(multiply, under_divide), Decimal.mult(divide, under_multiply)}
         end),
       offset: Decimal.new(0),
       numerator: numerator,
       denominator: denominator
     }}
  end

  def ratio(%Unit{}, %Unit{}), do: :error

  @doc "The dimension of a unit or of the text that names one, or `nil`."
  @spec dimension(term) :: Unit.dimension() | nil
  def dimension(unit) do
    case parse(unit) do
      {:ok, %Unit{dimension: dimension}} -> dimension
      :error -> nil
    end
  end

  @doc "Whether the unit counts things: a tablet, a capsule, a drop."
  @spec count?(Unit.t()) :: boolean
  def count?(%Unit{dimension: dimension}), do: dimension in @counts

  @doc """
  A number of one unit in another unit of the same dimension.

      iex> {:ok, pounds} = Rescord.Units.convert(Decimal.new("2.26796185"), "kg", "lb")
      iex> Decimal.to_string(pounds)
      "5"

      iex> Rescord.Units.convert(Decimal.new(1), "kg", "scoop")
      {:error, :unknown_unit}
  """
  @spec convert(Decimal.t() | integer, unit, unit) ::
          {:ok, Decimal.t()}
          | {:error, :unknown_unit | :not_the_same_dimension | :not_a_number}
  def convert(value, from, to) when is_integer(value), do: convert(Decimal.new(value), from, to)

  def convert(%Decimal{} = value, from, to) do
    with true <- finite?(value) || {:error, :not_a_number},
         {:ok, from} <- known(from),
         {:ok, to} <- known(to) do
      cond do
        from == to -> {:ok, value}
        from.dimension != to.dimension -> {:error, :not_the_same_dimension}
        true -> {:ok, exactly(fn -> rescale(value, from, to) end)}
      end
    end
  end

  def convert(_value, _from, _to), do: {:error, :not_a_number}

  @doc "Whether a number of the first unit converts to the second."
  @spec convertible?(term, term) :: boolean
  def convertible?(from, to) do
    case {parse(from), parse(to)} do
      {{:ok, from}, {:ok, to}} -> from.dimension == to.dimension
      _unknown -> false
    end
  end

  @doc """
  The product of a ratio and a quantity that fits what the ratio is for
  each of: `5 mg/kg` times `12.5 kg` is `62.5 mg`. The quantity converts to
  the unit of the ratio first, so a weight in grams fits a rate for each
  kilogram. The order of the two does not matter.

      iex> alias Rescord.Units.Quantity
      iex> {:ok, rate} = Quantity.parse("5 mg/kg")
      iex> {:ok, weight} = Quantity.parse("12500 g")
      iex> {:ok, dose} = Rescord.Units.multiply(weight, rate)
      iex> to_string(dose)
      "62.5 mg"

      iex> alias Rescord.Units.Quantity
      iex> {:ok, rate} = Quantity.parse("5 mg/kg")
      iex> {:ok, volume} = Quantity.parse("2 mL")
      iex> Rescord.Units.multiply(rate, volume)
      {:error, :units_do_not_fit}
  """
  @spec multiply(Quantity.t(), Quantity.t()) :: {:ok, Quantity.t()} | {:error, :units_do_not_fit}
  def multiply(
        %Quantity{unit: %Unit{numerator: %Unit{} = numerator, denominator: denominator}} = rate,
        %Quantity{unit: %Unit{numerator: nil}} = amount
      ) do
    case convert(amount.value, amount.unit, denominator) do
      {:ok, value} ->
        {:ok,
         %Quantity{value: exactly(fn -> Decimal.mult(rate.value, value) end), unit: numerator}}

      {:error, _reason} ->
        {:error, :units_do_not_fit}
    end
  end

  def multiply(
        %Quantity{unit: %Unit{numerator: nil}} = amount,
        %Quantity{unit: %Unit{numerator: %Unit{}}} = rate
      ),
      do: multiply(rate, amount)

  def multiply(%Quantity{}, %Quantity{}), do: {:error, :units_do_not_fit}

  @doc """
  One quantity divided by another.

    * A quantity by a ratio of its dimension gives what the ratio is for
      each of: `62.5 mg` by `50 mg/mL` is `1.25 mL`, and `100 mg` by
      `50 mg/tablet` is `2 tablet`.
    * A quantity by a quantity gives their ratio: `62.5 mg` by `12.5 kg`
      is `5 mg/kg`.
    * A ratio by a ratio with the same thing above gives what is below,
      the second for each of the first: `5 mg/kg` by `50 mg/mL` is
      `0.1 mL/kg`.

      iex> alias Rescord.Units.Quantity
      iex> {:ok, dose} = Quantity.parse("100 mg")
      iex> {:ok, strength} = Quantity.parse("50 mg/tablet")
      iex> {:ok, tablets} = Rescord.Units.divide(dose, strength)
      iex> to_string(tablets)
      "2 tablet"

      iex> alias Rescord.Units.Quantity
      iex> {:ok, dose} = Quantity.parse("100 mg")
      iex> {:ok, nothing} = Quantity.parse("0 mg/mL")
      iex> Rescord.Units.divide(dose, nothing)
      {:error, :division_by_zero}
  """
  @spec divide(Quantity.t(), Quantity.t()) ::
          {:ok, Quantity.t()} | {:error, :units_do_not_fit | :division_by_zero}
  def divide(
        %Quantity{unit: %Unit{numerator: nil}} = amount,
        %Quantity{unit: %Unit{numerator: %Unit{} = numerator, denominator: denominator}} = rate
      ) do
    with {:ok, value} <- fit(convert(amount.value, amount.unit, numerator)),
         {:ok, result} <- quotient(value, rate.value) do
      {:ok, %Quantity{value: result, unit: denominator}}
    end
  end

  def divide(
        %Quantity{unit: %Unit{numerator: nil} = over} = amount,
        %Quantity{unit: %Unit{numerator: nil} = under} = other
      ) do
    with {:ok, unit} <- fit(ratio(over, under)),
         {:ok, result} <- quotient(amount.value, other.value) do
      {:ok, %Quantity{value: result, unit: unit}}
    end
  end

  def divide(
        %Quantity{unit: %Unit{numerator: %Unit{} = over, denominator: under}} = rate,
        %Quantity{unit: %Unit{numerator: %Unit{}, denominator: other_under}} = other
      ) do
    with {:ok, same_over} <- fit(ratio(over, other_under)),
         {:ok, value} <- fit(convert(other.value, other.unit, same_over)),
         {:ok, unit} <- fit(ratio(other_under, under)),
         {:ok, result} <- quotient(rate.value, value) do
      {:ok, %Quantity{value: result, unit: unit}}
    end
  end

  def divide(%Quantity{}, %Quantity{}), do: {:error, :units_do_not_fit}

  @doc """
  The sum of two quantities of one dimension, in the unit of the first. A
  temperature has no sum.

      iex> alias Rescord.Units.Quantity
      iex> {:ok, one} = Quantity.parse("1.2 kg")
      iex> {:ok, other} = Quantity.parse("300 g")
      iex> {:ok, sum} = Rescord.Units.add(one, other)
      iex> to_string(sum)
      "1.5 kg"
  """
  @spec add(Quantity.t(), Quantity.t()) ::
          {:ok, Quantity.t()} | {:error, :not_the_same_dimension | :units_do_not_fit}
  def add(%Quantity{} = one, %Quantity{} = other), do: combine(one, other, &Decimal.add/2)

  @doc "The first quantity less the second, in the unit of the first."
  @spec subtract(Quantity.t(), Quantity.t()) ::
          {:ok, Quantity.t()} | {:error, :not_the_same_dimension | :units_do_not_fit}
  def subtract(%Quantity{} = one, %Quantity{} = other), do: combine(one, other, &Decimal.sub/2)

  defp combine(%Quantity{unit: %Unit{dimension: :temperature}}, _other, _operation),
    do: {:error, :units_do_not_fit}

  defp combine(%Quantity{} = one, %Quantity{} = other, operation) do
    case convert(other.value, other.unit, one.unit) do
      {:ok, value} ->
        {:ok, %Quantity{value: exactly(fn -> operation.(one.value, value) end), unit: one.unit}}

      {:error, _reason} ->
        {:error, :not_the_same_dimension}
    end
  end

  # ((value - offset) x multiply / divide) is the number in the base unit.
  # The work is one division, after each multiplication, so that a result
  # that can be exact is exact.
  defp rescale(value, from, to) do
    {from_multiply, from_divide} = from.scale
    {to_multiply, to_divide} = to.scale

    value
    |> Decimal.sub(from.offset)
    |> Decimal.mult(from_multiply)
    |> Decimal.mult(to_divide)
    |> Decimal.div(Decimal.mult(from_divide, to_multiply))
    |> Decimal.add(to.offset)
  end

  defp quotient(value, by) do
    if Decimal.equal?(by, 0) do
      {:error, :division_by_zero}
    else
      {:ok, exactly(fn -> Decimal.div(value, by) end)}
    end
  end

  defp fit({:ok, value}), do: {:ok, value}
  defp fit(_no), do: {:error, :units_do_not_fit}

  defp known(unit) do
    case parse(unit) do
      {:ok, unit} -> {:ok, unit}
      :error -> {:error, :unknown_unit}
    end
  end

  defp simple(text) do
    case @exact do
      %{^text => unit} -> {:ok, unit}
      _none -> Map.fetch(@folded, String.downcase(text))
    end
  end

  defp tidy(text), do: text |> String.trim() |> String.replace(~r/\s+/u, " ")

  defp finite?(%Decimal{coef: coef}), do: is_integer(coef)

  defp exactly(work), do: Decimal.Context.with(@context, work)
end
