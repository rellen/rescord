defmodule Rescord.Lists.GroupKind do
  @moduledoc "The values of the dimension `group kind` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "group_kinds", base: Rescord.Lists.Base.GroupKind
end
