defmodule Rescord.Journal.Standard do
  @moduledoc """
  A measurement as a page shows it (ADR 0094): in the standard unit of its
  kind, beside what the person recorded.

  The record keeps what was typed. Rescord converts when it reads, so a new
  standard unit of a kind shows each old measurement in the new unit.

    * A kind with no standard unit: the measurement as it was recorded.
    * A measurement in the standard unit: as it was recorded, and
      `standard?` is true.
    * A measurement in a unit that Rescord converts to the standard unit
      (ADR 0071): the converted value, and `converted?` is true.
    * A measurement that does not convert, such as an old one with no unit:
      as it was recorded, and `standard?` is false.

  No number is rounded here: a page rounds.
  """

  alias Rescord.Units

  @enforce_keys [:value, :recorded]
  defstruct [
    :value,
    :unit_label,
    :unit,
    :recorded,
    :recorded_unit,
    standard?: false,
    converted?: false
  ]

  @type t :: %__MODULE__{
          value: Decimal.t(),
          unit_label: String.t() | nil,
          unit: Units.Unit.t() | nil,
          recorded: Decimal.t(),
          recorded_unit: String.t() | nil,
          standard?: boolean,
          converted?: boolean
        }

  @doc """
  The measurement in the standard unit of its kind. The measurement has its
  unit, and its kind with the standard unit, each with the label, as
  `Rescord.Journal.entries/2` loads them.
  """
  @spec of(map) :: t
  def of(%{value: %Decimal{} = value} = measurement) do
    unit = loaded(Map.get(measurement, :unit))
    standard = standard_unit(measurement)

    recorded = %__MODULE__{
      value: value,
      unit_label: label(unit),
      unit: known(unit),
      recorded: value,
      recorded_unit: label(unit)
    }

    cond do
      is_nil(standard) ->
        recorded

      unit != nil and unit.id == standard.id ->
        %{recorded | standard?: true}

      true ->
        with %{} = from <- recorded.unit,
             %{} = to <- known(standard),
             {:ok, converted} <- Units.convert(value, from, to) do
          %{
            recorded
            | value: converted,
              unit_label: label(standard),
              unit: to,
              standard?: true,
              converted?: true
          }
        else
          _does_not_convert -> recorded
        end
    end
  end

  @doc "The standard unit of the kind of a measurement, a value of the list of units, or `nil`."
  @spec standard_unit(map) :: map | nil
  def standard_unit(measurement) do
    case loaded(Map.get(measurement, :measure_kind)) do
      nil -> nil
      kind -> loaded(Map.get(kind, :standard_unit))
    end
  end

  @doc "The unit of the catalogue that a value of the list of units means, or `nil`."
  @spec known(map | nil) :: Units.Unit.t() | nil
  def known(nil), do: nil

  def known(unit) do
    case Rescord.Lists.known_unit(unit) do
      {:ok, known} -> known
      :error -> nil
    end
  end

  @doc "The name of a value of the list of units, or `nil`."
  @spec label(map | nil) :: String.t() | nil
  def label(nil), do: nil
  def label(unit), do: to_string(unit.label)

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(value), do: value
end
