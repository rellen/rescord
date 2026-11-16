defmodule Rescord.Journal.Diagnosis do
  @moduledoc "The condition that a journal entry of the kind `diagnosis` names."

  use Rescord.Journal.Detail, table: "diagnoses", accept: [:condition_id]

  relationships do
    belongs_to :condition, Rescord.Lists.Condition do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
