defmodule Rescord.Lists.TaskKind do
  @moduledoc "The values of the dimension `task kind` that one organisation uses."

  use Rescord.Lists.OrganisationList, table: "task_kinds", base: Rescord.Lists.Base.TaskKind
end
