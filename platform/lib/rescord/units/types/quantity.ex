defmodule Rescord.Units.Types.Quantity do
  @moduledoc """
  The Ash type of a quantity (ADR 0071): a `Rescord.Units.Quantity`, a
  number with its unit.

  The database holds a map, `{"value": "0.2", "unit": "mL"}`. The number is
  a text there, so that no digit is lost, and the unit is the one that the
  person wrote: nothing converts to a base unit.

  It reads a `Rescord.Units.Quantity`, a text such as `"0.2 mL"`, and a
  map with `value` and `unit`, so a form needs one field or two.

  The constraints:

    * `dimension` - one dimension or a list of them, such as
      `{:mass, :mass}` for a dose rate;
    * `positive?` - the number must be more than zero.

      argument :strength, Rescord.Units.Types.Quantity do
        constraints dimension: [{:mass, :volume}, {:mass, :tablet}], positive?: true
      end
  """

  use Ash.Type

  alias Rescord.Units.Quantity
  alias Rescord.Units.Types.Unit, as: UnitType

  @impl true
  def constraints do
    [
      dimension: [
        type: :any,
        doc:
          "The dimension that the unit must have, such as `:mass` or `{:mass, :volume}`, or a list of them"
      ],
      positive?: [
        type: :boolean,
        default: false,
        doc: "Whether the number must be more than zero"
      ]
    ]
  end

  @impl true
  def storage_type(_constraints), do: :map

  @impl true
  def matches_type?(%Quantity{}, _constraints), do: true
  def matches_type?(_other, _constraints), do: false

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(%Quantity{} = quantity, _constraints), do: {:ok, quantity}

  def cast_input(text, _constraints) when is_binary(text) do
    if String.valid?(text) and String.trim(text) == "" do
      {:ok, nil}
    else
      text |> Quantity.parse() |> cast()
    end
  end

  def cast_input(%{} = map, _constraints) when not is_struct(map) do
    value = field(map, :value)
    unit = field(map, :unit)

    if blank?(value) and blank?(unit) do
      {:ok, nil}
    else
      Quantity.new(value, unit) |> cast()
    end
  end

  def cast_input(_other, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(%Quantity{} = quantity, _constraints), do: {:ok, quantity}

  def cast_stored(%{} = map, _constraints) when not is_struct(map) do
    case Quantity.new(field(map, :value), field(map, :unit)) do
      {:ok, quantity} -> {:ok, quantity}
      {:error, _reason} -> :error
    end
  end

  def cast_stored(_other, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(%Quantity{} = quantity, _constraints),
    do: {:ok, %{"value" => Quantity.plain(quantity), "unit" => quantity.unit.code}}

  def dump_to_native(_other, _constraints), do: :error

  @impl true
  def apply_constraints(nil, _constraints), do: {:ok, nil}

  def apply_constraints(%Quantity{} = quantity, constraints) do
    cond do
      not UnitType.allowed?(quantity.unit, constraints[:dimension]) ->
        {:error, "has a unit of the wrong kind"}

      constraints[:positive?] && not Quantity.positive?(quantity) ->
        {:error, "must be more than zero"}

      true ->
        {:ok, quantity}
    end
  end

  # `1.0 kg` and `1 kg` are the same, so a write of one over the other is
  # no change.
  @impl true
  def equal?(%Quantity{} = one, %Quantity{} = other), do: Quantity.equal?(one, other)
  def equal?(one, other), do: one == other

  defp cast({:ok, quantity}), do: {:ok, quantity}
  defp cast({:error, :not_a_number}), do: {:error, "must be a number and a unit, such as 0.2 mL"}
  defp cast({:error, :unknown_unit}), do: {:error, "has a unit that Rescord does not know"}

  defp field(map, key) do
    case map do
      %{^key => value} -> value
      _text_keys -> Map.get(map, Atom.to_string(key))
    end
  end

  defp blank?(nil), do: true
  defp blank?(text) when is_binary(text), do: String.trim(text) == ""
  defp blank?(_other), do: false
end
