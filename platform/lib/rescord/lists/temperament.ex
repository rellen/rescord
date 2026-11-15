defmodule Rescord.Lists.Temperament do
  @moduledoc "The values of the dimension `temperament` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "temperaments", base: Rescord.Lists.Base.Temperament
end
