defmodule Rescord.Lists.Colour do
  @moduledoc "The values of the dimension `colour` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "colours", base: Rescord.Lists.Base.Colour
end
