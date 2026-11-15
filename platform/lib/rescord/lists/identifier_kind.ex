defmodule Rescord.Lists.IdentifierKind do
  @moduledoc "The values of the dimension `identifier kind` that one organisation uses."

  use Rescord.Lists.OrganisationList,
    table: "identifier_kinds",
    base: Rescord.Lists.Base.IdentifierKind
end
