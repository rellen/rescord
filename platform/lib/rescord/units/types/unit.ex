defmodule Rescord.Units.Types.Unit do
  @moduledoc """
  The Ash type of a unit of measure (ADR 0071): a `Rescord.Units.Unit`,
  stored as the text of its code, such as `"mg/kg"`.

  It reads the text that a person typed with `Rescord.Units.parse/1`, so a
  form sends a symbol or a name. A text that names no unit is not valid.

  The constraint `dimension` is one dimension or a list of them:

      attribute :unit, Rescord.Units.Types.Unit do
        constraints dimension: [:mass, :volume]
      end
  """

  use Ash.Type

  alias Rescord.Units
  alias Rescord.Units.Unit

  @impl true
  def constraints do
    [
      dimension: [
        type: :any,
        doc:
          "The dimension that the unit must have, such as `:mass` or `{:mass, :volume}`, or a list of them"
      ]
    ]
  end

  @impl true
  def storage_type(_constraints), do: :string

  @impl true
  def matches_type?(%Unit{}, _constraints), do: true
  def matches_type?(_other, _constraints), do: false

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}
  def cast_input(%Unit{} = unit, _constraints), do: {:ok, unit}

  def cast_input(%Ash.CiString{} = text, constraints),
    do: cast_input(to_string(text), constraints)

  def cast_input(text, _constraints) when is_binary(text) do
    if String.valid?(text) and String.trim(text) == "" do
      {:ok, nil}
    else
      case Units.parse(text) do
        {:ok, unit} -> {:ok, unit}
        :error -> {:error, "is not a unit that Rescord knows"}
      end
    end
  end

  def cast_input(_other, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(%Unit{} = unit, _constraints), do: {:ok, unit}
  def cast_stored(code, _constraints) when is_binary(code), do: Units.parse(code)
  def cast_stored(_other, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(%Unit{code: code}, _constraints), do: {:ok, code}
  def dump_to_native(_other, _constraints), do: :error

  @impl true
  def apply_constraints(nil, _constraints), do: {:ok, nil}

  def apply_constraints(%Unit{} = unit, constraints) do
    if allowed?(unit, constraints[:dimension]) do
      {:ok, unit}
    else
      {:error, "is not a unit of the right kind"}
    end
  end

  @doc "Whether a unit has one of the dimensions of the constraint. No constraint allows each unit."
  @spec allowed?(Unit.t(), term) :: boolean
  def allowed?(%Unit{}, nil), do: true
  def allowed?(%Unit{dimension: dimension}, allowed), do: dimension in List.wrap(allowed)
end
