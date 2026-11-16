defmodule Rescord.Lists.ProcedureKind do
  @moduledoc "The values of the dimension `procedure kind` that one organisation uses."

  use Rescord.Lists.OrganisationList,
    table: "procedure_kinds",
    base: Rescord.Lists.Base.ProcedureKind
end
