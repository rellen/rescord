defmodule Rescord.Lists.MeasureKind do
  @moduledoc """
  The values of the dimension `measure kind` that one organisation uses.

  A kind lists the units that a measurement of it can have, for example a
  weight in `g` or `kg` (the maintainer, 18 November 2026). A form of a
  measurement offers only those units. A kind with no unit in its list
  accepts each unit of the organisation, until an administrator gives it
  some.
  """

  use Rescord.Lists.OrganisationList, table: "measure_kinds", base: Rescord.Lists.Base.MeasureKind

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

  actions do
    update :set_units do
      description "Gives the units that a measurement of this kind can have"
      accept [:unit_ids]
    end
  end
end
