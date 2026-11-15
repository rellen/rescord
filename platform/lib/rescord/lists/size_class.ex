defmodule Rescord.Lists.SizeClass do
  @moduledoc "The values of the dimension `size class` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "size_classes", base: Rescord.Lists.Base.SizeClass
end
