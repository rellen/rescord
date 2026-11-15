defmodule Rescord.Lists.Species do
  @moduledoc "The values of the dimension `species` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "species", base: Rescord.Lists.Base.Species
end
