defmodule RescordWeb.MeasurementUnits do
  @moduledoc """
  The units that a form of a measurement offers (ADR 0094), for the journal
  page and for the page of the measurements.

  A kind with a standard unit offers that unit first, and then each unit
  that Rescord converts to it. A form chooses the standard unit when the
  person chooses the kind, and offers no measurement with no unit. A kind
  with no standard unit offers its units, or each unit, and "No unit".
  `Rescord.Lists.accepted_units/2` decides, as for the rule of the journal.
  """

  alias Rescord.Lists

  defstruct kinds: %{}, units: []

  @type t :: %__MODULE__{kinds: %{String.t() => map}, units: [map]}

  @doc "Reads the measure kinds and the units of an organisation, as the person."
  @spec read(keyword) :: t
  def read(options) do
    {:ok, kinds} = Lists.values(:measure_kind, options)
    {:ok, units} = Lists.values(:unit, options)
    %__MODULE__{kinds: Map.new(kinds, &{&1.id, &1}), units: units}
  end

  @doc """
  The options of the unit for a kind, each as its name and its id. No form
  offers a retired unit. With no kind, or a kind that the lists do not
  have, each unit.
  """
  @spec options(t, term) :: [{String.t(), String.t()}]
  def options(%__MODULE__{} = lists, kind_id) do
    accepted =
      case Map.get(lists.kinds, kind_id) do
        nil -> lists.units
        kind -> Lists.accepted_units(kind, lists.units)
      end

    for unit <- accepted, not unit.retired, do: {to_string(unit.label), unit.id}
  end

  @doc """
  If a measurement of a kind needs a unit: the kind has a standard unit.
  A retired standard unit still decides, as in the rule of the journal,
  so the form does not offer "No unit" and then have the journal refuse it.
  """
  @spec needed?(t, term) :: boolean
  def needed?(%__MODULE__{} = lists, kind_id) do
    case Map.get(lists.kinds, kind_id) do
      %{standard_unit_id: id} when is_binary(id) -> Enum.any?(lists.units, &(&1.id == id))
      _none -> false
    end
  end

  @doc """
  The id of the standard unit of a kind, when a form can offer it, or
  `nil`: the kind has none, or the unit is retired.
  """
  @spec standard(t, term) :: String.t() | nil
  def standard(%__MODULE__{} = lists, kind_id) do
    with %{standard_unit_id: id} when is_binary(id) <- Map.get(lists.kinds, kind_id),
         %{retired: false} <- Enum.find(lists.units, &(&1.id == id)) do
      id
    else
      _none -> nil
    end
  end
end
