defmodule Rescord.UnitsTest do
  @moduledoc """
  The catalogue of units and the arithmetic on quantities (ADR 0071). Each
  factor has a line here with a number from outside the catalogue.
  """

  use ExUnit.Case, async: true

  alias Rescord.Units
  alias Rescord.Units.{Quantity, Unit}

  doctest Units
  doctest Quantity

  defp convert!(number, from, to) do
    {:ok, value} = Units.convert(Decimal.new(number), from, to)
    value
  end

  defp quantity!(text) do
    {:ok, quantity} = Quantity.parse(text)
    quantity
  end

  defp same?(one, other), do: Decimal.equal?(one, Decimal.new(other))

  describe "the factors" do
    # {a number, its unit, the same amount, its unit}
    @facts [
      {"1", "mg", "1000", "mcg"},
      {"1", "g", "1000", "mg"},
      {"1", "kg", "1000", "g"},
      {"1", "kg", "1000000000", "mcg"},
      {"1", "lb", "453.59237", "g"},
      {"1", "oz", "28.349523125", "g"},
      {"1", "lb", "16", "oz"},
      {"1", "L", "1000", "mL"},
      {"1", "m", "100", "cm"},
      {"1", "cm", "10", "mm"},
      {"1", "in", "25.4", "mm"},
      {"1", "min", "60", "s"},
      {"1", "h", "60", "min"},
      {"1", "d", "24", "h"},
      {"1", "kcal", "4.184", "kJ"},
      {"37", "°C", "98.6", "°F"},
      {"0", "°C", "32", "°F"},
      {"-40", "°C", "-40", "°F"},
      {"38.5", "°C", "101.3", "°F"}
    ]

    for {number, unit, same, other} <- @facts do
      test "#{number} #{unit} is #{same} #{other}" do
        assert same?(convert!(unquote(number), unquote(unit), unquote(other)), unquote(same))
        assert same?(convert!(unquote(same), unquote(other), unquote(unit)), unquote(number))
      end
    end

    test "a number goes to each unit of its dimension and comes back" do
      for from <- Units.all(), to <- Units.units_of(from.dimension) do
        there = convert!("12.5", from, to)
        back = convert!(there, to, from)

        assert same?(Decimal.round(back, 20), "12.5"),
               "12.5 #{from.symbol} came back from #{to.symbol} as #{back}"
      end
    end

    test "a unit converts to itself with no change to the number" do
      assert Units.convert(Decimal.new("1.50"), "kg", "kilograms") == {:ok, Decimal.new("1.50")}
    end

    test "a whole number converts as a decimal" do
      assert {:ok, value} = Units.convert(2, "kg", "g")
      assert same?(value, "2000")
    end

    test "a result that cannot be exact has 28 digits" do
      assert Decimal.to_string(convert!("1", "kg", "lb")) == "2.204622621848775807229738013"
    end

    test "the precision does not follow the process" do
      Decimal.Context.with(%Decimal.Context{precision: 3}, fn ->
        assert same?(convert!("1234.5678", "g", "kg"), "1.2345678")
      end)
    end
  end

  describe "what does not convert" do
    test "two dimensions" do
      assert Units.convert(Decimal.new(1), "kg", "mL") == {:error, :not_the_same_dimension}
      assert Units.convert(Decimal.new(1), "mg/kg", "mg/mL") == {:error, :not_the_same_dimension}
      assert Units.convert(Decimal.new(1), "mg", "mg/kg") == {:error, :not_the_same_dimension}
    end

    test "a count, and an international unit" do
      assert Units.convert(Decimal.new(1), "tablet", "capsule") ==
               {:error, :not_the_same_dimension}

      assert Units.convert(Decimal.new(1), "IU", "mg") == {:error, :not_the_same_dimension}
      assert Units.convert(Decimal.new(1), "drop", "mL") == {:error, :not_the_same_dimension}
    end

    test "a unit that the catalogue does not have" do
      assert Units.convert(Decimal.new(1), "bag", "kg") == {:error, :unknown_unit}
      assert Units.convert(Decimal.new(1), "kg", "bag") == {:error, :unknown_unit}
    end

    test "a float, and a number that is no number" do
      assert Units.convert(1.5, "kg", "g") == {:error, :not_a_number}
      assert Units.convert(Decimal.new("NaN"), "kg", "g") == {:error, :not_a_number}
      assert Units.convert(Decimal.new("Infinity"), "kg", "g") == {:error, :not_a_number}
      assert Units.convert("1.5", "kg", "g") == {:error, :not_a_number}
    end

    test "convertible?/2 says so first" do
      assert Units.convertible?("g", "lb")
      refute Units.convertible?("g", "mL")
      refute Units.convertible?("g", "bag")
    end
  end

  describe "parse/1" do
    test "reads a symbol, a name and the other spellings" do
      for {text, symbol} <- [
            {"kg", "kg"},
            {"KG", "kg"},
            {"Kilograms", "kg"},
            {" kilo ", "kg"},
            {"ml", "mL"},
            {"ML", "mL"},
            {"millilitre", "mL"},
            {"milliliters", "mL"},
            {"cc", "mL"},
            {"l", "L"},
            {"µg", "mcg"},
            {"μg", "mcg"},
            {"ug", "mcg"},
            {"MCG", "mcg"},
            {"lbs", "lb"},
            {"degC", "°C"},
            {"deg  F", "°F"},
            {"℃", "°C"},
            {"tabs", "tablet"},
            {"Capsules", "capsule"},
            {"iu", "IU"},
            {"hr", "h"},
            {"kj", "kJ"}
          ] do
        assert {:ok, %Unit{symbol: ^symbol}} = Units.parse(text), "#{inspect(text)}"
      end
    end

    test "reads a ratio with a stroke or with `per`" do
      for text <- ["mg/kg", "mg / kg", "MG/KG", "mg per kg", "milligrams per kilogram"] do
        assert {:ok, %Unit{symbol: "mg/kg", dimension: {:mass, :mass}} = unit} = Units.parse(text)
        assert unit.numerator.symbol == "mg"
        assert unit.denominator.symbol == "kg"
        assert unit.name == "milligram per kilogram"
        assert unit.key == {:milligram, :kilogram}
      end

      assert {:ok, %Unit{dimension: {:mass, :tablet}}} = Units.parse("mg/tablet")
      assert {:ok, %Unit{dimension: {:international_unit, :volume}}} = Units.parse("IU/mL")
      assert {:ok, %Unit{dimension: {:volume, :time}}} = Units.parse("mL/h")
    end

    test "the same unit is the same struct, however a person wrote it" do
      assert Units.parse("mg/kg") == Units.parse("Milligrams per KG")
      assert Units.parse("ml") == Units.parse("mL")
    end

    test "refuses what names no unit" do
      for text <- ["", " ", "bag", "scoop", "mg/", "/kg", "mg/kg/d", "mg/bag", "kgg", "m g"] do
        assert Units.parse(text) == :error, "#{inspect(text)}"
      end

      assert Units.parse(nil) == :error
      assert Units.parse(:kg) == :error
      assert Units.parse(<<0xFF, 0xFE>>) == :error
    end

    test "a temperature is no part of a ratio" do
      assert Units.parse("°C/h") == :error
      assert Units.parse("mg/°C") == :error
    end

    test "the code of each unit reads back as the unit" do
      ratios =
        for one <- Units.all(),
            other <- Units.all(),
            {:ok, unit} <- [Units.ratio(one, other)],
            do: unit

      for unit <- Units.all() ++ ratios do
        assert Units.parse(unit.code) == {:ok, unit}
        assert to_string(unit) == unit.code
      end
    end

    test "a unit is JSON as its code" do
      {:ok, unit} = Units.parse("mg/kg")
      assert Jason.encode!(unit) == ~s("mg/kg")
    end
  end

  describe "the catalogue" do
    test "has the units of a dose" do
      assert Enum.map(Units.units_of(:mass), & &1.symbol) == ~w(mcg mg g kg oz lb)
      assert Enum.map(Units.units_of(:volume), & &1.symbol) == ~w(mL L)
      assert Units.units_of(:nothing) == []
    end

    test "each unit is in one dimension of the list" do
      assert Units.dimensions() ==
               [
                 :mass,
                 :volume,
                 :length,
                 :temperature,
                 :time,
                 :energy,
                 :tablet,
                 :capsule,
                 :drop,
                 :international_unit
               ]

      for unit <- Units.all(), do: assert(unit.dimension in Units.dimensions())
    end

    test "a count is a tablet, a capsule or a drop" do
      counts = for unit <- Units.all(), Units.count?(unit), do: unit.symbol
      assert counts == ~w(tablet capsule drop)
    end

    test "writes a microgram as mcg, and never with a µ" do
      for unit <- Units.all(), do: refute(unit.symbol =~ ~r/[µμ]/u)
    end
  end

  describe "multiply/2" do
    test "a dose rate and a weight give the dose" do
      assert {:ok, dose} = Units.multiply(quantity!("5 mg/kg"), quantity!("12.5 kg"))
      assert dose.unit.symbol == "mg"
      assert same?(dose.value, "62.5")
    end

    test "the weight converts to the unit of the rate first" do
      assert {:ok, dose} = Units.multiply(quantity!("5 mg/kg"), quantity!("10 lb"))
      assert dose.unit.symbol == "mg"
      assert same?(dose.value, "22.6796185")
    end

    test "a strength and a volume give the mass, in each order" do
      assert {:ok, mass} = Units.multiply(quantity!("0.4 mL"), quantity!("50 mg/mL"))
      assert to_string(mass) == "20 mg"

      assert {:ok, units} = Units.multiply(quantity!("100 IU/mL"), quantity!("0.05 mL"))
      assert to_string(units) == "5 IU"
    end

    test "refuses what does not fit the ratio" do
      assert Units.multiply(quantity!("5 mg/kg"), quantity!("2 mL")) ==
               {:error, :units_do_not_fit}

      assert Units.multiply(quantity!("5 mg"), quantity!("2 kg")) == {:error, :units_do_not_fit}

      assert Units.multiply(quantity!("5 mg/kg"), quantity!("2 mg/mL")) ==
               {:error, :units_do_not_fit}
    end
  end

  describe "divide/2" do
    test "a dose and a strength give the volume" do
      assert {:ok, volume} = Units.divide(quantity!("62.5 mg"), quantity!("50 mg/mL"))
      assert to_string(volume) == "1.25 mL"
    end

    test "the dose converts to the unit of the strength first" do
      assert {:ok, volume} = Units.divide(quantity!("0.5 g"), quantity!("50 mg/mL"))
      assert to_string(volume) == "10 mL"

      assert {:ok, volume} = Units.divide(quantity!("250 mcg"), quantity!("1 mg/mL"))
      assert to_string(volume) == "0.25 mL"
    end

    test "a dose and the strength of a tablet give the tablets" do
      assert {:ok, tablets} = Units.divide(quantity!("75 mg"), quantity!("50 mg/tablet"))
      assert to_string(tablets) == "1.5 tablet"
    end

    test "a dose and a weight give the rate, which does not cancel" do
      assert {:ok, rate} = Units.divide(quantity!("62.5 mg"), quantity!("12.5 kg"))
      assert to_string(rate) == "5 mg/kg"

      assert {:ok, rate} = Units.divide(quantity!("2 g"), quantity!("4 g"))
      assert to_string(rate) == "0.5 g/g"
    end

    test "a rate and a strength give the volume for each kilogram" do
      assert {:ok, rate} = Units.divide(quantity!("5 mg/kg"), quantity!("50 mg/mL"))
      assert to_string(rate) == "0.1 mL/kg"

      assert {:ok, rate} = Units.divide(quantity!("5 mg/kg"), quantity!("50 g/L"))
      assert to_string(rate) == "0.0001 L/kg"
    end

    test "a division that does not end has 28 digits" do
      assert {:ok, volume} = Units.divide(quantity!("1 mg"), quantity!("3 mg/mL"))
      assert Decimal.to_string(volume.value) == "0.3333333333333333333333333333"
    end

    test "refuses zero, and what does not fit" do
      assert Units.divide(quantity!("1 mg"), quantity!("0 mg/mL")) == {:error, :division_by_zero}
      assert Units.divide(quantity!("1 mg"), quantity!("0 kg")) == {:error, :division_by_zero}
      assert Units.divide(quantity!("1 mL"), quantity!("5 mg/mL")) == {:error, :units_do_not_fit}
      assert Units.divide(quantity!("5 mg/mL"), quantity!("1 mg")) == {:error, :units_do_not_fit}
      assert Units.divide(quantity!("38 °C"), quantity!("1 h")) == {:error, :units_do_not_fit}

      assert Units.divide(quantity!("5 mg/kg"), quantity!("5 mL/kg")) ==
               {:error, :units_do_not_fit}
    end
  end

  describe "add/2 and subtract/2" do
    test "give the unit of the first quantity" do
      assert {:ok, sum} = Units.add(quantity!("300 g"), quantity!("1.2 kg"))
      assert to_string(sum) == "1500 g"

      assert {:ok, change} = Units.subtract(quantity!("1.095 kg"), quantity!("1000 g"))
      assert to_string(change) == "0.095 kg"
    end

    test "refuse two dimensions, and a temperature" do
      assert Units.add(quantity!("1 kg"), quantity!("1 mL")) == {:error, :not_the_same_dimension}

      assert Units.subtract(quantity!("1 kg"), quantity!("1 mL")) ==
               {:error, :not_the_same_dimension}

      assert Units.add(quantity!("38 °C"), quantity!("1 °C")) == {:error, :units_do_not_fit}
    end
  end

  describe "a quantity" do
    test "comes from a number and a unit" do
      assert {:ok, %Quantity{} = quantity} = Quantity.new(Decimal.new("0.20"), "ml")
      assert quantity.unit.symbol == "mL"
      assert Quantity.new(5, "mg/kg") == Quantity.parse("5 mg/kg")
      assert Quantity.new(" 0.5 ", "mg") == Quantity.parse("0.5mg")
    end

    test "comes from the text of a person" do
      for {text, written} <- [
            {"12.5 kg", "12.5 kg"},
            {"12.5kg", "12.5 kg"},
            {"  0.20   mL ", "0.2 mL"},
            {".5 mg", "0.5 mg"},
            {"-2 °C", "-2 °C"},
            {"+3 g", "3 g"},
            {"2 tablets", "2 tablet"},
            {"5 Mg / Kg", "5 mg/kg"},
            {"1000 IU", "1000 IU"}
          ] do
        assert {:ok, quantity} = Quantity.parse(text), "#{inspect(text)}"
        assert to_string(quantity) == written
      end
    end

    test "refuses a float, a comma, an exponent and words" do
      assert Quantity.new(0.5, "mg") == {:error, :not_a_number}
      assert Quantity.new("1,5", "mg") == {:error, :not_a_number}
      assert Quantity.new("NaN", "mg") == {:error, :not_a_number}
      assert Quantity.new(Decimal.new("Infinity"), "mg") == {:error, :not_a_number}
      assert Quantity.new(nil, "mg") == {:error, :not_a_number}
      assert Quantity.new("1", nil) == {:error, :unknown_unit}

      assert Quantity.parse("1,5 kg") == {:error, :not_a_number}
      assert Quantity.parse("1,095 g") == {:error, :not_a_number}
      assert Quantity.parse("half a tablet") == {:error, :not_a_number}
      assert Quantity.parse("") == {:error, :not_a_number}
      assert Quantity.parse(nil) == {:error, :not_a_number}
      assert Quantity.parse("5") == {:error, :unknown_unit}
      assert Quantity.parse("12.5") == {:error, :unknown_unit}
      assert Quantity.parse("5 scoops") == {:error, :unknown_unit}
      assert Quantity.parse("1e3 g") == {:error, :unknown_unit}
    end

    test "converts, and keeps what cannot convert" do
      assert {:ok, pounds} = Quantity.convert(quantity!("2.26796185 kg"), "lb")
      assert to_string(pounds) == "5 lb"
      assert Quantity.convert(quantity!("1 kg"), "mL") == {:error, :not_the_same_dimension}
      assert Quantity.convert(quantity!("1 kg"), "bag") == {:error, :unknown_unit}
    end

    test "rounds half up, to two places unless told" do
      assert to_string(Quantity.round(quantity!("1.125 mL"))) == "1.13 mL"
      assert to_string(Quantity.round(quantity!("1.124 mL"))) == "1.12 mL"
      assert to_string(Quantity.round(quantity!("1.25 mL"), 1)) == "1.3 mL"
      assert to_string(Quantity.round(quantity!("1.25 mL"), 1, :half_even)) == "1.2 mL"
      assert to_string(Quantity.round(quantity!("1249 g"), -2)) == "1200 g"
    end

    test "multiplies by a plain number" do
      assert to_string(Quantity.times(quantity!("0.2 mL"), 3)) == "0.6 mL"
      assert to_string(Quantity.times(quantity!("0.2 mL"), Decimal.new("1.5"))) == "0.3 mL"
    end

    test "compares by the amount, and is equal by the number and the unit" do
      assert Quantity.compare(quantity!("1000 g"), quantity!("1 kg")) == {:ok, :eq}
      assert Quantity.compare(quantity!("1 lb"), quantity!("1 kg")) == {:ok, :lt}
      assert Quantity.compare(quantity!("39 °C"), quantity!("100 °F")) == {:ok, :gt}

      assert Quantity.compare(quantity!("1 g"), quantity!("1 mL")) ==
               {:error, :not_the_same_dimension}

      assert Quantity.equal?(quantity!("1.0 kg"), quantity!("1 kg"))
      refute Quantity.equal?(quantity!("1000 g"), quantity!("1 kg"))
    end

    test "says whether it is more than zero" do
      assert Quantity.positive?(quantity!("0.1 mg"))
      refute Quantity.positive?(quantity!("0 mg"))
      refute Quantity.positive?(quantity!("-1 °C"))
    end

    test "is text with no exponent, and JSON with the number as text" do
      {:ok, large} = Quantity.convert(quantity!("12.5 kg"), "mcg")
      assert to_string(large) == "12500000000 mcg"

      assert Jason.decode!(Jason.encode!(quantity!("0.20 mL"))) == %{
               "value" => "0.2",
               "unit" => "mL"
             }
    end
  end
end
