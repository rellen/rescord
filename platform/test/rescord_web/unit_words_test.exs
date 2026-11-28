defmodule RescordWeb.UnitWordsTest do
  use ExUnit.Case, async: true

  alias Rescord.Units
  alias Rescord.Units.Quantity
  alias RescordWeb.UnitWords

  doctest UnitWords

  defp words(text) do
    {:ok, quantity} = Quantity.parse(text)
    UnitWords.quantity(quantity)
  end

  test "a quantity is its number as each number of a page, and then the symbol" do
    assert words("1095 g") == "1,095 g"
    assert words("0.20 mL") == "0.2 mL"
    assert words("5 mg/kg") == "5 mg/kg"
    assert words("38.5 °C") == "38.5 °C"
    assert words("12500000 mcg") == "12,500,000 mcg"
    assert words("1000 IU") == "1,000 IU"
  end

  test "a quantity keeps each digit" do
    assert words("0.00025 mg") == "0.00025 mg"
    assert words("0.3333333333333333333333333333 mL") == "0.3333333333333333333333333333 mL"
  end

  test "a count has a plural, and a ratio of a count does not" do
    assert words("1 tablet") == "1 tablet"
    assert words("1.0 tablet") == "1 tablet"
    assert words("2 tablet") == "2 tablets"
    assert words("0.5 capsule") == "0.5 capsules"
    assert words("3 drops") == "3 drops"
    assert words("50 mg/tablet") == "50 mg/tablet"
  end

  test "each dimension of the catalogue has words" do
    for dimension <- Units.dimensions() do
      assert UnitWords.dimension(dimension) =~ ~r/^an? /
    end
  end

  test "each unit of the catalogue says what it is" do
    for unit <- Units.all() do
      assert UnitWords.meaning(unit) == "#{unit.name}, #{UnitWords.dimension(unit.dimension)}"
    end

    {:ok, rate} = Units.parse("mg/kg")
    assert UnitWords.meaning(rate) == "milligram per kilogram"
  end
end
