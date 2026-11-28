defmodule Rescord.Lists.MeasureKind do
  @moduledoc """
  The values of the dimension `measure kind` that one organisation uses.

  A kind lists the units that a measurement of it can have, for example a
  weight in `g` or `kg` (the maintainer, 18 November 2026). A form of a
  measurement offers only those units. A kind with no unit in its list
  accepts each unit of the organisation, until an administrator gives it
  some.

  A kind names its standard unit (ADR 0094): the unit in which a page, a
  chart, a report and the export show each measurement of the kind. A
  measurement can have another unit that Rescord converts to it, and keeps
  what the person typed. A kind with no standard unit, such as a score,
  shows each measurement as it was recorded.
  `Rescord.Lists.accepted_units/2` gives the units that a measurement of a
  kind can have.
  """

  use Rescord.Lists.OrganisationList, table: "measure_kinds", base: Rescord.Lists.Base.MeasureKind

  postgres do
    references do
      # No key in the database. A key between two temporal tables holds for
      # each instant of the row of the kind, and a kind can be older than
      # its standard unit. The action checks that the unit is there, and no
      # action removes a unit: an administrator retires it.
      reference :standard_unit, ignore?: true
    end
  end

  attributes do
    # The ids of values of `Rescord.Lists.Unit`. A list of plain ids: a
    # retired unit stays in the list, and a page shows it as retired.
    attribute :unit_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
      description "The units that a measurement of this kind can have. None: each unit"
    end
  end

  relationships do
    belongs_to :standard_unit, Rescord.Lists.Unit do
      public? true
      temporal_keys {:valid_at, :valid_at}

      description "The unit in which Rescord shows each measurement of this kind. None: as recorded"
    end
  end

  actions do
    update :set_units do
      description "Gives the units that a measurement of this kind can have"
      # The validation and the change read the record.
      require_atomic? false
      accept [:unit_ids]

      validate Rescord.Lists.Validations.StandardUnit
      change Rescord.Lists.Changes.OneUnitIsStandard
    end

    update :set_standard_unit do
      description "Gives the unit in which Rescord shows each measurement of this kind, or takes it away"
      # The validation reads the list of units.
      require_atomic? false
      accept [:standard_unit_id]

      validate Rescord.Lists.Validations.StandardUnit
    end
  end
end
