defmodule Rescord.Lists.Unit do
  @moduledoc "The values of the dimension `unit` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "units", base: Rescord.Lists.Base.Unit
end
