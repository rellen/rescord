defmodule Rescord.Journal.Calculations.InStandardUnit do
  @moduledoc """
  A measurement in the standard unit of its kind (ADR 0094), for the export
  of the data: `field: :value` is the number, with no rounding, and
  `field: :unit` is the name of the standard unit.

  Both are `nil` for a measurement of a kind with no standard unit, and for
  one that Rescord does not convert to it. The record itself keeps what
  the person recorded.
  """

  use Ash.Resource.Calculation

  alias Rescord.Journal.Standard

  # The calculation reads through Ash only, as of the instant of the read.
  def temporal_safe?(_opts), do: true

  @impl true
  def load(_query, _opts, _context),
    do: [unit: [:label], measure_kind: [standard_unit: [:label]]]

  @impl true
  def calculate(records, opts, _context) do
    field = Keyword.fetch!(opts, :field)

    {:ok,
     Enum.map(records, fn record ->
       case {Standard.of(record), field} do
         {%Standard{standard?: true} = standard, :value} -> standard.value
         {%Standard{standard?: true} = standard, :unit} -> standard.unit_label
         _as_recorded -> nil
       end
     end)}
  end
end
