defmodule Rescord.Journal.Measurement do
  @moduledoc """
  The value that a journal entry of the kind `measurement` records, for
  example a weight of 1,095 g. The weight of a resident has its history
  here (`docs/domain.md`, section 5.2).
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
