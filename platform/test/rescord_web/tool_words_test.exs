defmodule RescordWeb.ToolWordsTest do
  @moduledoc """
  Holds the words of the tools to `Rescord.Dosage`: each problem and each
  note has words, the words name nothing that the calculator cannot say,
  and a quantity and a step of the working read as a person writes them.
  """

  use ExUnit.Case, async: true

  alias Rescord.Dosage
  alias Rescord.Units.Quantity
  alias RescordWeb.ToolWords

  defp quantity(text) do
    {:ok, quantity} = Quantity.parse(text)
    quantity
  end

  test "each problem of a calculation has words" do
    assert Enum.sort(ToolWords.problems()) == Enum.sort(Dosage.problems())

    for problem <- Dosage.problems() do
      words = ToolWords.problem(problem)
      assert words =~ ~r/\A[A-Z].*\.\z/, inspect(problem)
      refute words =~ "_"
    end
  end

  test "the words for a number that is not a number say how to write one" do
    for field <- [:weight, :rate, :strength] do
      assert ToolWords.problem({field, :not_a_number}) =~ "no comma"
    end
  end

  test "each note of a result has words, which send the person to a vet" do
    assert Enum.sort(ToolWords.notes()) == Enum.sort(Dosage.notes())
    for note <- Dosage.notes(), do: assert(ToolWords.note(note) =~ "Ask your vet")
  end

  test "a quantity is its number and its unit, and tablets are counted in words" do
    assert ToolWords.quantity(quantity("1095 g")) == "1,095 g"
    assert ToolWords.quantity(quantity("0.146 mL")) == "0.146 mL"
    assert ToolWords.quantity(quantity("84 mcg")) == "84 mcg"
    assert ToolWords.quantity(quantity("1 tablet")) == "1 tablet"
    assert ToolWords.quantity(quantity("1.24 tablet")) == "1.24 tablets"
  end

  test "a number that the calculator worked out has three figures, and says if it was rounded" do
    assert ToolWords.worked(quantity("0.146 mL")) == "0.146 mL"
    assert ToolWords.worked(quantity("2.3333333333 mL")) == "about 2.33 mL"
    assert ToolWords.worked(quantity("1.81436948 mL")) == "about 1.81 mL"
    assert ToolWords.worked(quantity("1.81436948 mL"), 6) == "about 1.81437 mL"
    assert ToolWords.worked(quantity("0.9996 tablet")) == "about 1 tablet"
  end

  test "a dose rate and a strength are sentences, with no slash" do
    assert ToolWords.rate(quantity("0.2 mg/kg")) == "0.2 mg for each kg of body weight"
    assert ToolWords.rate(quantity("0.5 mL/kg")) == "0.5 mL for each kg of body weight"
    assert ToolWords.strength(quantity("1.5 mg/mL")) == "1.5 mg in each mL"
    assert ToolWords.strength(quantity("50 mg/tablet")) == "50 mg in each tablet"
  end

  test "a step of the working is a line of arithmetic" do
    assert ToolWords.step({:convert, quantity("1095 g"), quantity("1.095 kg")}) ==
             "1,095 g = 1.095 kg"

    assert ToolWords.step(
             {:multiply, quantity("1.095 kg"), quantity("0.2 mg/kg"), quantity("0.219 mg")}
           ) == "1.095 kg × 0.2 mg/kg = 0.219 mg"

    assert ToolWords.step(
             {:divide, quantity("7 mg"), quantity("3 mg/mL"), quantity("2.3333333333 mL")}
           ) == "7 mg ÷ 3 mg/mL = about 2.33333 mL"

    assert ToolWords.step(
             {:divide, quantity("62 mg"), quantity("50 mg/tablet"), quantity("1.24 tablet")}
           ) == "62 mg ÷ 50 mg/tablet = 1.24 tablets"
  end
end
