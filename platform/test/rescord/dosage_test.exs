defmodule Rescord.DosageTest do
  @moduledoc """
  Holds the arithmetic of a dose (ADR 0072): a table of examples that a
  person calculated by hand, each guard with a value that it must refuse,
  and the rounding of a result for a page.
  """

  use ExUnit.Case, async: true

  alias Rescord.Dosage
  alias Rescord.Dosage.Result
  alias Rescord.Units.Quantity

  doctest Rescord.Dosage

  defp quantity(text) do
    {:ok, quantity} = Quantity.parse(text)
    quantity
  end

  defp typed(weight, rate, strength \\ nil) do
    [weight, weight_unit] = String.split(weight, " ")
    [rate, rate_unit] = String.split(rate, " ")

    base = %{weight: weight, weight_unit: weight_unit, rate: rate, rate_unit: rate_unit}

    case strength && String.split(strength, " ") do
      nil ->
        base

      [strength, unit, per] ->
        Map.merge(base, %{strength: strength, strength_unit: unit, strength_per: per})
    end
  end

  defp calculate!(weight, rate, strength \\ nil) do
    {:ok, given} = Dosage.read(typed(weight, rate, strength))
    {:ok, %Result{} = result} = Dosage.calculate(given)
    result
  end

  defp same?(%Quantity{} = quantity, text) do
    wanted = quantity(text)
    quantity.unit == wanted.unit and Decimal.equal?(quantity.value, wanted.value)
  end

  describe "the examples that a person calculated by hand" do
    # Each row: the weight, the dose rate for each kg, the strength, the
    # dose, and the amount of the product.
    @examples [
      # 1095 g = 1.095 kg; 1.095 × 0.2 = 0.219 mg; 0.219 ÷ 1.5 = 0.146 mL
      {"1095 g", "0.2 mg", "1.5 mg mL", "0.219 mg", "0.146 mL"},
      # 12.4 × 5 = 62 mg; 62 ÷ 50 = 1.24 tablets
      {"12.4 kg", "5 mg", "50 mg tablet", "62 mg", "1.24 tablet"},
      # 4.2 × 20 = 84 mcg = 0.084 mg; 0.084 ÷ 0.3 = 0.28 mL
      {"4.2 kg", "20 mcg", "0.3 mg mL", "84 mcg", "0.28 mL"},
      # 3.2 × 0.5 = 1.6 mL, and no strength
      {"3.2 kg", "0.5 mL", nil, "1.6 mL", nil},
      # 30 g = 0.03 kg; 0.03 × 10 = 0.3 mg
      {"30 g", "10 mg", nil, "0.3 mg", nil},
      # 2 lb = 0.90718474 kg; × 10 = 9.0718474 mg; ÷ 5 = 1.81436948 mL
      {"2 lb", "10 mg", "5 mg mL", "9.0718474 mg", "1.81436948 mL"},
      # 8 oz = 0.226796185 kg; × 2 = 0.45359237 mg
      {"8 oz", "2 mg", nil, "0.45359237 mg", nil},
      # 5 × 1 = 5 g = 5000 mg; 5000 ÷ 500 = 10 tablets
      {"5 kg", "1 g", "500 mg tablet", "5 g", "10 tablet"},
      # 0.4 × 250 = 100 mcg; 100 ÷ 50 = 2 mL
      {"0.4 kg", "250 mcg", "50 mcg mL", "100 mcg", "2 mL"}
    ]

    for {weight, rate, strength, dose, amount} <- @examples do
      test "#{weight} at #{rate} for each kg#{strength && ", with #{strength}"}" do
        result = calculate!(unquote(weight), unquote(rate), unquote(strength))

        assert same?(result.dose, unquote(dose)), "the dose is #{result.dose}"

        case unquote(amount) do
          nil -> assert result.amount == nil
          amount -> assert same?(result.amount, amount), "the amount is #{result.amount}"
        end
      end
    end

    test "the amount times the strength is the weight times the rate" do
      for weight <- ~w(0.03 0.75 4.2 12.4 37 610),
          rate <- ~w(0.01 0.2 5 22.5),
          strength <- ~w(0.5 1.5 10 250) do
        result = calculate!("#{weight} kg", "#{rate} mg", "#{strength} mg mL")

        back = Decimal.mult(result.amount.value, Decimal.new(strength))
        dose = Decimal.mult(Decimal.new(weight), Decimal.new(rate))

        # A division keeps 28 digits, so the way back is equal to 20.
        assert Decimal.equal?(Decimal.round(back, 20), Decimal.round(dose, 20)),
               "#{weight} kg at #{rate} mg/kg with #{strength} mg/mL gave #{result.amount}"
      end
    end

    test "no number has a zero after its last digit" do
      result = calculate!("12.40 kg", "5.0 mg", "50.00 mg tablet")

      assert Decimal.to_string(result.dose.value, :normal) == "62"
      assert Decimal.to_string(result.amount.value, :normal) == "1.24"
    end
  end

  describe "the steps of the working" do
    test "a weight in the unit of the rate is multiplied, and that is all" do
      result = calculate!("12.4 kg", "5 mg")

      assert [{:multiply, weight, rate, dose}] = result.steps
      assert same?(weight, "12.4 kg")
      assert same?(rate, "5 mg/kg")
      assert same?(dose, "62 mg")
    end

    test "a weight in another unit is converted first, in a step of its own" do
      result = calculate!("1095 g", "0.2 mg", "1.5 mg mL")

      assert [
               {:convert, grams, kilograms},
               {:multiply, kilograms, _rate, dose},
               {:divide, dose, strength, amount}
             ] = result.steps

      assert same?(grams, "1095 g")
      assert same?(kilograms, "1.095 kg")
      assert same?(strength, "1.5 mg/mL")
      assert same?(amount, "0.146 mL")
    end

    test "a dose in another unit than the strength is converted before the division" do
      result = calculate!("4.2 kg", "20 mcg", "0.3 mg mL")

      assert [
               {:multiply, _weight, _rate, micrograms},
               {:convert, micrograms, milligrams},
               {:divide, milligrams, _strength, amount}
             ] = result.steps

      assert same?(micrograms, "84 mcg")
      assert same?(milligrams, "0.084 mg")
      assert same?(amount, "0.28 mL")
    end

    test "the result holds what went in" do
      result = calculate!("1095 g", "0.2 mg", "1.5 mg mL")

      assert same?(result.weight, "1095 g")
      assert same?(result.rate, "0.2 mg/kg")
      assert same?(result.strength, "1.5 mg/mL")
    end
  end

  describe "a number that a person typed" do
    test "is digits with at most one point" do
      for text <- ~w(1 12 0.5 1095 12.4 0.000001 9999999.999999 007) do
        assert {:ok, %Decimal{}} = Dosage.parse_number(text), text
      end

      assert Dosage.parse_number("  4.2\n") == {:ok, Decimal.new("4.2")}
    end

    test "is refused with a comma, a sign, an exponent, a space or another mark" do
      for text <-
            ["1,095", "1,5", "-1", "+1", "1e3", "1E3", ".5", "5.", "1 0", "1.2.3", "0x10"] ++
              ["１２", "1_000", "NaN", "Infinity", "four", "5kg", "1/2", "½"] do
        assert Dosage.parse_number(text) == {:error, :not_a_number}, text
      end
    end

    test "is refused with more digits than a weight or a dose has" do
      assert Dosage.parse_number("12345678") == {:error, :not_a_number}
      assert Dosage.parse_number("0.1234567") == {:error, :not_a_number}
    end

    test "is refused when it is zero" do
      for text <- ~w(0 0.0 000 0.000000) do
        assert Dosage.parse_number(text) == {:error, :not_positive}, text
      end
    end

    test "is blank with no mark, or with nothing" do
      assert Dosage.parse_number("") == {:error, :blank}
      assert Dosage.parse_number("   ") == {:error, :blank}
      assert Dosage.parse_number(nil) == {:error, :blank}
    end

    test "is refused when it is no text" do
      for value <- [12, 1.5, ["1"], %{"a" => "1"}, :one] do
        assert Dosage.parse_number(value) == {:error, :not_a_number}
      end
    end
  end

  describe "what a person typed and chose" do
    test "says each value that it refuses, and not only the first" do
      typed = %{
        weight: "1,095",
        weight_unit: "g",
        rate: "",
        rate_unit: "mg",
        strength: "-2",
        strength_unit: "mg",
        strength_per: "mL"
      }

      assert Dosage.read(typed) ==
               {:error, [weight: :not_a_number, rate: :blank, strength: :not_a_number]}
    end

    test "has no strength when its number is blank" do
      assert {:ok, %{strength: nil}} = Dosage.read(typed("4 kg", "2 mg"))

      assert {:ok, %{strength: nil}} =
               Dosage.read(
                 Map.merge(typed("4 kg", "2 mg"), %{strength: " ", strength_unit: "mg"})
               )
    end

    test "has no strength for a dose rate that gives a volume, whatever was typed there" do
      typed = Map.merge(typed("4 kg", "2 mL"), %{strength: "1,5", strength_unit: "st"})

      assert {:ok, %{strength: nil}} = Dosage.read(typed)
    end

    test "refuses a unit that the calculator does not offer" do
      # A stone is no unit of the catalogue. A kilogram is no unit of a dose
      # rate, an international unit is no unit of a dose here, and a litre
      # is not what a strength is in each of.
      for {change, field} <- [
            {%{weight_unit: "st"}, :weight},
            {%{weight_unit: "mg"}, :weight},
            {%{weight_unit: "mL"}, :weight},
            {%{weight_unit: nil}, :weight},
            {%{weight_unit: ["kg"]}, :weight},
            {%{rate_unit: "kg"}, :rate},
            {%{rate_unit: "IU"}, :rate},
            {%{rate_unit: "mg/lb"}, :rate},
            {%{rate_unit: "µg"}, :rate},
            {%{strength_unit: "mL"}, :strength},
            {%{strength_unit: "IU"}, :strength},
            {%{strength_per: "L"}, :strength},
            {%{strength_per: "kg"}, :strength},
            {%{strength_per: "capsule"}, :strength}
          ] do
        typed = Map.merge(typed("4 kg", "2 mg", "5 mg mL"), change)

        assert Dosage.read(typed) == {:error, [{field, :unknown_unit}]}, inspect(change)
      end
    end

    test "offers the units of the design, the first of each list first" do
      symbols = fn units -> Enum.map(units, & &1.symbol) end

      assert symbols.(Dosage.weight_units()) == ~w(kg g lb oz)
      assert symbols.(Dosage.dose_units()) == ~w(mg mcg g mL)
      assert symbols.(Dosage.strength_units()) == ~w(mg mcg g)
      assert symbols.(Dosage.strength_per()) == ~w(mL tablet)
    end

    test "knows which dose rate gives a volume" do
      assert Dosage.volume?("mL")
      refute Dosage.volume?("mg")
      refute Dosage.volume?("L")
      refute Dosage.volume?(nil)
      refute Dosage.volume?(["mL"])
    end
  end

  describe "the quantities of a calculation, whoever made them" do
    test "a weight that is no mass is refused" do
      for weight <- ["5 mL", "5 tablet", "5 mg/kg", "5 IU"] do
        assert Dosage.calculate(%{weight: quantity(weight), rate: quantity("5 mg/kg")}) ==
                 {:error, [weight: :not_a_weight]},
               weight
      end
    end

    test "a dose rate that is no amount for each mass is refused" do
      for rate <- ["5 mg", "5 mg/mL", "5 mg/tablet", "5 IU/kg", "5 kg"] do
        assert Dosage.calculate(%{weight: quantity("4 kg"), rate: quantity(rate)}) ==
                 {:error, [rate: :not_a_dose_rate]},
               rate
      end
    end

    test "a strength that is no mass in each volume or tablet is refused" do
      for strength <- ["5 mg", "5 mL/kg", "5 mg/kg", "5 IU/mL", "5 mL"] do
        assert Dosage.calculate(%{
                 weight: quantity("4 kg"),
                 rate: quantity("5 mg/kg"),
                 strength: quantity(strength)
               }) == {:error, [strength: :not_a_strength]},
               strength
      end
    end

    test "a strength with a dose rate that gives a volume is refused, and not ignored" do
      assert Dosage.calculate(%{
               weight: quantity("4 kg"),
               rate: quantity("0.5 mL/kg"),
               strength: quantity("5 mg/mL")
             }) == {:error, [strength: :not_for_a_volume]}
    end

    test "a number that is not above zero is refused" do
      zero = fn text -> %{quantity(text) | value: Decimal.new(0)} end
      below = fn text -> %{quantity(text) | value: Decimal.new("-1")} end

      assert Dosage.calculate(%{weight: zero.("4 kg"), rate: quantity("5 mg/kg")}) ==
               {:error, [weight: :not_positive]}

      assert Dosage.calculate(%{weight: quantity("4 kg"), rate: below.("5 mg/kg")}) ==
               {:error, [rate: :not_positive]}

      assert Dosage.calculate(%{
               weight: quantity("4 kg"),
               rate: quantity("5 mg/kg"),
               strength: zero.("5 mg/mL")
             }) == {:error, [strength: :not_positive]}
    end

    test "each problem is said, and not only the first" do
      assert Dosage.calculate(%{
               weight: quantity("4 mL"),
               rate: quantity("5 mg"),
               strength: quantity("5 mg")
             }) ==
               {:error,
                [weight: :not_a_weight, rate: :not_a_dose_rate, strength: :not_a_strength]}
    end

    test "what is no quantity gives no result" do
      assert Dosage.calculate(%{weight: "4 kg", rate: "5 mg/kg"}) ==
               {:error, [calculation: :units_do_not_fit]}

      assert Dosage.calculate(nil) == {:error, [calculation: :units_do_not_fit]}
    end

    test "a dose rate for each gram converts the weight to grams" do
      result =
        Dosage.calculate(%{weight: quantity("2 kg"), rate: quantity("0.005 mg/g")})

      assert {:ok, %Result{steps: [{:convert, _kilograms, grams}, {:multiply, _, _, dose}]}} =
               result

      assert same?(grams, "2000 g")
      assert same?(dose, "10 mg")
    end
  end

  describe "a result that is too small to measure" do
    test "is a volume of less than 0.01 mL" do
      # 0.1 × 0.01 = 0.001 mg; 0.001 ÷ 1 = 0.001 mL
      assert calculate!("0.1 kg", "0.01 mg", "1 mg mL").notes == [:too_small_to_measure]
      # 0.03 × 0.3 = 0.009 mL
      assert calculate!("0.03 kg", "0.3 mL").notes == [:too_small_to_measure]
    end

    test "is not a volume of 0.01 mL or more" do
      # 1 × 0.01 = 0.01 mg; 0.01 ÷ 1 = 0.01 mL
      assert calculate!("1 kg", "0.01 mg", "1 mg mL").notes == []
      assert calculate!("3.2 kg", "0.5 mL").notes == []
    end

    test "is less than a quarter of a tablet" do
      # 1 × 1 = 1 mg; 1 ÷ 10 = 0.1 tablet
      assert calculate!("1 kg", "1 mg", "10 mg tablet").notes == [:less_than_a_quarter]
    end

    test "is not a quarter of a tablet or more" do
      # 2.5 × 1 = 2.5 mg; 2.5 ÷ 10 = 0.25 tablet
      assert calculate!("2.5 kg", "1 mg", "10 mg tablet").notes == []
    end

    test "is never a dose as a mass, which has no syringe and no tablet" do
      assert calculate!("0.01 kg", "0.01 mcg").notes == []
    end
  end

  describe "the rounding of a result for a page" do
    test "keeps three figures, rounded half up, and says if that is exact" do
      for {number, rounded, exact?} <- [
            {"0.146", "0.146", true},
            {"1.24", "1.24", true},
            {"62", "62", true},
            {"0.1465", "0.147", false},
            {"0.1464", "0.146", false},
            {"2.333333333333333333333333333", "2.33", false},
            {"1.81436948", "1.81", false},
            {"1234.5", "1230", false},
            {"1235", "1240", false},
            {"0.9996", "1", false},
            {"0.000123456", "0.000123", false},
            {"100", "100", true},
            {"0.10", "0.1", true}
          ] do
        {shown, same?} = Dosage.round_figures(Decimal.new(number))

        assert Decimal.to_string(shown, :normal) == rounded, number
        assert same? == exact?, number
      end
    end

    test "keeps the figures that a page asks for" do
      {shown, exact?} = Dosage.round_figures(Decimal.new("2.333333333333333333333333333"), 6)

      assert Decimal.to_string(shown, :normal) == "2.33333"
      refute exact?
    end

    test "leaves zero as it is" do
      assert Dosage.round_figures(Decimal.new("0.000")) == {Decimal.new(0), true}
    end
  end

  describe "a quantity of a record" do
    defp parsed(text) do
      {:ok, quantity} = Rescord.Units.Quantity.parse(text)
      quantity
    end

    test "is a body weight in a unit of weight of the calculator, above zero" do
      for text <- ["1095 g", "1.2 kg", "3 lb", "10 oz"] do
        assert Dosage.weight?(parsed(text)), text
      end

      for text <- ["5 mg", "0 kg", "2 mL", "5 mg/kg", "1 tablet", "12345678 g", "0.1234567 kg"] do
        refute Dosage.weight?(parsed(text)), text
      end

      refute Dosage.weight?(nil)
      refute Dosage.weight?("1095 g")
    end

    test "is a strength as a mass in each mL or in each tablet, above zero" do
      for text <- ["1.5 mg/mL", "50 mg/tablet", "100 mcg/mL", "1 g/tablet"] do
        assert Dosage.strength?(parsed(text)), text
      end

      for text <- ["5 mg/kg", "5 mg", "0 mg/mL", "1 mL/kg", "5 mg/capsule", "5 kg/mL"] do
        refute Dosage.strength?(parsed(text)), text
      end

      refute Dosage.strength?(nil)
    end

    test "is read from the form of a record with the guards of the calculator" do
      assert {:ok, strength} = Dosage.strength(" 1.5 ", "mg", "mL")
      assert to_string(strength) == "1.5 mg/mL"
      assert Dosage.strength?(strength)

      assert Dosage.strength("", "mg", "mL") == {:ok, nil}
      assert Dosage.strength(nil, nil, nil) == {:ok, nil}
      assert Dosage.strength("1,5", "mg", "mL") == {:error, :not_a_number}
      assert Dosage.strength("0", "mg", "mL") == {:error, :not_positive}
      assert Dosage.strength("1.5", "kg", "mL") == {:error, :unknown_unit}
      assert Dosage.strength("1.5", "mg", "kg") == {:error, :unknown_unit}
      assert Dosage.strength("1.5", %{}, ["mL"]) == {:error, :unknown_unit}
    end
  end
end
