defmodule Rescord.Lists.LocationKind do
  @moduledoc "The values of the dimension `location kind` that one organisation uses."

  use Rescord.Lists.OrganisationList,
    table: "location_kinds",
    base: Rescord.Lists.Base.LocationKind
end
