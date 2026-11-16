defmodule Rescord.Lists.MeasureKind do
  @moduledoc "The values of the dimension `measure kind` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "measure_kinds", base: Rescord.Lists.Base.MeasureKind
end
