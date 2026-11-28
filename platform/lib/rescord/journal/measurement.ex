defmodule Rescord.Journal.Measurement do
  @moduledoc """
  The value that a journal entry of the kind `measurement` records, for
  example a weight of 1,095 g. The weight of a resident has its history
  here (`docs/domain.md`, section 5.2).

  The record keeps the value and the unit that the person recorded. A page
  shows a measurement in the standard unit of its kind
  (`Rescord.Journal.standard/1`, ADR 0094), and the export has it in the
  two calculations `standard_value` and `standard_unit`.
  """

  use Rescord.Journal.Detail,
    table: "measurements",
    accept: [:measure_kind_id, :value, :unit_id]

  attributes do
    attribute :value, :decimal do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :standard_value,
              :decimal,
              {Rescord.Journal.Calculations.InStandardUnit, field: :value} do
      public? true

      description "The value in the standard unit of the kind. None: the kind has no standard unit, or Rescord does not convert the unit"
    end

    calculate :standard_unit,
              :string,
              {Rescord.Journal.Calculations.InStandardUnit, field: :unit} do
      public? true
      description "The name of the standard unit of the kind, when `standard_value` has a value"
    end
  end

  relationships do
    belongs_to :measure_kind, Rescord.Lists.MeasureKind do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :unit, Rescord.Lists.Unit do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
