defmodule Rescord.Journal.Dose do
  @moduledoc """
  A dose of a medication that a member gave: the journal entry of the kind
  `dose`. It can name the prescription that it is a part of. A completed
  `medicate` task writes such an entry (`docs/domain.md`, section 5.7).
  """

  use Rescord.Journal.Detail, table: "doses", accept: [:prescription_id, :amount]

  attributes do
    attribute :amount, :string do
      public? true
      constraints max_length: 120
      description "How much the member gave, in words"
    end
  end

  relationships do
    belongs_to :prescription, Rescord.Journal.Prescription do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
