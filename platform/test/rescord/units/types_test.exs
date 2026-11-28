defmodule Rescord.Units.TypesTest do
  @moduledoc """
  The Ash types of a unit and of a quantity (ADR 0071): what they read,
  what they refuse, and what the database holds.
  """

  use Rescord.DataCase, async: true

  alias Rescord.Units
  alias Rescord.Units.Quantity
  alias Rescord.Units.Types

  alias Rescord.UnitsFixtures.Bottle

  defp quantity!(text) do
    {:ok, quantity} = Quantity.parse(text)
    quantity
  end

  defp unit!(text) do
    {:ok, unit} = Units.parse(text)
    unit
  end

  defp fill(input), do: Bottle |> Ash.Changeset.for_create(:fill, input) |> Ash.create()

  defp messages(%Ash.Error.Invalid{errors: errors}),
    do: Enum.map(errors, &{&1.field, &1.message})

  describe "the type of a quantity" do
    test "reads a quantity, a text and a map" do
      expected = quantity!("0.2 mL")

      for input <- [
            expected,
            "0.2 mL",
            " 0.20ml ",
            %{"value" => "0.2", "unit" => "ml"},
            %{value: Decimal.new("0.2"), unit: "mL"},
            %{"value" => "0.2", "unit" => unit!("mL")}
          ] do
        assert {:ok, quantity} = Ash.Type.cast_input(Types.Quantity, input, [])
        assert Quantity.equal?(quantity, expected), "#{inspect(input)}"
      end
    end

    test "reads nothing as nothing" do
      for input <- [nil, "", "  ", %{"value" => "", "unit" => ""}, %{}] do
        assert Ash.Type.cast_input(Types.Quantity, input, []) == {:ok, nil}
      end
    end

    test "refuses a text that is no quantity, and says why" do
      assert {:error, "must be a number and a unit, such as 0.2 mL"} =
               Ash.Type.cast_input(Types.Quantity, "a little", [])

      assert {:error, "must be a number and a unit, such as 0.2 mL"} =
               Ash.Type.cast_input(Types.Quantity, %{"value" => "", "unit" => "mL"}, [])

      assert {:error, "has a unit that Rescord does not know"} =
               Ash.Type.cast_input(Types.Quantity, "2 scoops", [])

      assert {:error, "has a unit that Rescord does not know"} =
               Ash.Type.cast_input(Types.Quantity, %{"value" => "2", "unit" => ""}, [])

      assert {:error, _invalid} = Ash.Type.cast_input(Types.Quantity, 0.2, [])
      assert {:error, _invalid} = Ash.Type.cast_input(Types.Quantity, {2, "mL"}, [])
    end

    test "holds the dimension and the sign of its constraints" do
      {:ok, constraints} =
        Ash.Type.init(Types.Quantity,
          dimension: [{:mass, :volume}, {:mass, :tablet}],
          positive?: true
        )

      assert {:ok, %Quantity{}} =
               Ash.Type.apply_constraints(Types.Quantity, quantity!("50 mg/mL"), constraints)

      assert {:ok, %Quantity{}} =
               Ash.Type.apply_constraints(Types.Quantity, quantity!("50 mg/tablet"), constraints)

      assert {:error, _wrong_kind} =
               Ash.Type.apply_constraints(Types.Quantity, quantity!("50 mg"), constraints)

      assert {:error, _wrong_kind} =
               Ash.Type.apply_constraints(Types.Quantity, quantity!("50 mL/kg"), constraints)

      assert {:error, _not_positive} =
               Ash.Type.apply_constraints(Types.Quantity, quantity!("0 mg/mL"), constraints)

      assert {:ok, nil} = Ash.Type.apply_constraints(Types.Quantity, nil, constraints)
    end

    test "with no constraint takes each unit and each sign" do
      {:ok, constraints} = Ash.Type.init(Types.Quantity, [])

      assert {:ok, %Quantity{}} =
               Ash.Type.apply_constraints(Types.Quantity, quantity!("-2 °C"), constraints)
    end

    test "stores a map with the number as text, and reads it back" do
      quantity = quantity!("0.000250 mg/kg")

      assert {:ok, stored} = Ash.Type.dump_to_native(Types.Quantity, quantity, [])
      assert stored == %{"value" => "0.00025", "unit" => "mg/kg"}

      assert {:ok, back} = Ash.Type.cast_stored(Types.Quantity, stored, [])
      assert Quantity.equal?(back, quantity)

      assert Ash.Type.dump_to_native(Types.Quantity, nil, []) == {:ok, nil}
      assert Ash.Type.cast_stored(Types.Quantity, nil, []) == {:ok, nil}
    end

    test "comes back from a jsonb column of PostgreSQL with each digit" do
      quantity = quantity!("1234567890.123456789012345678 mcg")
      {:ok, stored} = Ash.Type.dump_to_native(Types.Quantity, quantity, [])

      %{rows: [[from_database]]} = Rescord.Repo.query!("select $1::jsonb", [stored])

      assert {:ok, back} = Ash.Type.cast_stored(Types.Quantity, from_database, [])
      assert Quantity.equal?(back, quantity)
      assert back.unit == quantity.unit
    end

    test "refuses a stored map that names no unit of the catalogue" do
      assert Ash.Type.cast_stored(Types.Quantity, %{"value" => "1", "unit" => "bag"}, []) ==
               :error

      assert Ash.Type.cast_stored(Types.Quantity, %{"value" => "x", "unit" => "mg"}, []) == :error
      assert Ash.Type.cast_stored(Types.Quantity, "1 mg", []) == :error
    end

    test "says that 1.0 kg and 1 kg are equal, and that 1000 g is another value" do
      assert Ash.Type.equal?(Types.Quantity, quantity!("1.0 kg"), quantity!("1 kg"))
      refute Ash.Type.equal?(Types.Quantity, quantity!("1000 g"), quantity!("1 kg"))
      refute Ash.Type.equal?(Types.Quantity, nil, quantity!("1 kg"))
      assert Ash.Type.equal?(Types.Quantity, nil, nil)
    end
  end

  describe "the type of a unit" do
    test "reads a unit and a text, and stores the code" do
      for input <- [unit!("mg/kg"), "mg/kg", "Milligrams per kg", Ash.CiString.new("MG/KG")] do
        assert {:ok, unit} = Ash.Type.cast_input(Types.Unit, input, [])
        assert unit == unit!("mg/kg")
      end

      assert Ash.Type.dump_to_native(Types.Unit, unit!("mg/kg"), []) == {:ok, "mg/kg"}
      assert Ash.Type.cast_stored(Types.Unit, "mg/kg", []) == {:ok, unit!("mg/kg")}
      assert Ash.Type.cast_stored(Types.Unit, "bag", []) == :error
    end

    test "reads nothing as nothing, and refuses a name that it does not know" do
      assert Ash.Type.cast_input(Types.Unit, nil, []) == {:ok, nil}
      assert Ash.Type.cast_input(Types.Unit, " ", []) == {:ok, nil}

      assert {:error, "is not a unit that Rescord knows"} =
               Ash.Type.cast_input(Types.Unit, "bag", [])

      assert {:error, _invalid} = Ash.Type.cast_input(Types.Unit, 5, [])
    end

    test "holds the dimension of its constraint" do
      {:ok, one} = Ash.Type.init(Types.Unit, dimension: :mass)
      {:ok, some} = Ash.Type.init(Types.Unit, dimension: [:mass, {:mass, :mass}])

      assert {:ok, _unit} = Ash.Type.apply_constraints(Types.Unit, unit!("kg"), one)
      assert {:error, _wrong_kind} = Ash.Type.apply_constraints(Types.Unit, unit!("mL"), one)
      assert {:error, _wrong_kind} = Ash.Type.apply_constraints(Types.Unit, unit!("mg/kg"), one)
      assert {:ok, _unit} = Ash.Type.apply_constraints(Types.Unit, unit!("mg/kg"), some)
    end
  end

  describe "in a resource" do
    test "an attribute takes the text of a form and gives a quantity" do
      assert {:ok, bottle} = fill(%{strength: "50 mg/ml", counted_in: "ml"})
      assert to_string(bottle.strength) == "50 mg/mL"
      assert bottle.counted_in == unit!("mL")

      assert [read] = Ash.read!(Bottle)
      assert Quantity.equal?(read.strength, quantity!("50 mg/mL"))
    end

    test "an attribute refuses a wrong dimension, zero and words" do
      assert {:error, error} = fill(%{strength: "50 mg"})
      assert [{:strength, "has a unit of the wrong kind"}] = messages(error)

      assert {:error, error} = fill(%{strength: "0 mg/mL"})
      assert [{:strength, "must be more than zero"}] = messages(error)

      assert {:error, error} = fill(%{strength: "strong"})
      assert [{:strength, "must be a number and a unit, such as 0.2 mL"}] = messages(error)

      assert {:error, error} = fill(%{counted_in: "kg"})
      assert [{:counted_in, "is not a unit of the right kind"}] = messages(error)

      assert {:error, error} = fill(%{counted_in: "bag"})
      assert [{:counted_in, "is not a unit that Rescord knows"}] = messages(error)
    end

    test "a write of the same quantity with other zeros is no change" do
      {:ok, bottle} = fill(%{strength: "50 mg/mL"})

      same = Ash.Changeset.for_update(bottle, :change, %{strength: "50.0 mg/mL"})
      refute Ash.Changeset.changing_attribute?(same, :strength)

      other = Ash.Changeset.for_update(bottle, :change, %{strength: "50 g/L"})
      assert Ash.Changeset.changing_attribute?(other, :strength)
    end

    test "an action takes quantities as arguments and returns one" do
      input = Ash.ActionInput.for_action(Bottle, :dose, %{weight: "12.5 kg", rate: "5 mg/kg"})
      assert {:ok, dose} = Ash.run_action(input)
      assert to_string(dose) == "62.5 mg"

      refused = Ash.ActionInput.for_action(Bottle, :dose, %{weight: "12.5 mL", rate: "5 mg/kg"})
      assert {:error, %Ash.Error.Invalid{} = error} = Ash.run_action(refused)
      assert [{:weight, "has a unit of the wrong kind"}] = messages(error)
    end
  end
end
