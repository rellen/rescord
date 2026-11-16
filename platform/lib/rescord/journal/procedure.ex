defmodule Rescord.Journal.Procedure do
  @moduledoc "The kind of procedure that a journal entry of the kind `procedure` records."

  use Rescord.Journal.Detail, table: "procedures", accept: [:procedure_kind_id]

  relationships do
    belongs_to :procedure_kind, Rescord.Lists.ProcedureKind do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
