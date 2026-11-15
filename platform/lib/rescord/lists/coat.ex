defmodule Rescord.Lists.Coat do
  @moduledoc "The values of the dimension `coat` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "coats", base: Rescord.Lists.Base.Coat
end
