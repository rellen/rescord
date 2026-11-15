defmodule Rescord.Lists.Breed do
  @moduledoc "The values of the dimension `breed` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "breeds", base: Rescord.Lists.Base.Breed
end
