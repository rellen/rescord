defmodule Rescord.Lists.Condition do
  @moduledoc "The values of the dimension `condition` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "conditions", base: Rescord.Lists.Base.Condition
end
