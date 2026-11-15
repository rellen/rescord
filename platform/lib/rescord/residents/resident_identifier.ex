defmodule Rescord.Residents.ResidentIdentifier do
  @moduledoc """
  An identifier of a resident, for example the number of a microchip. A
  resident has zero identifiers or more, and each has a kind from the list of
  the organisation.

  The removal of an identifier archives it: the paper trail then says who
  removed it.
  """

  use Rescord.Residents.Fact, table: "resident_identifiers"

  actions do
    defaults [:read]

    create :add do
      accept [:resident_id, :kind_id, :value]
    end

    destroy :remove
  end

  attributes do
    attribute :value, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 60
    end
  end

  relationships do
    belongs_to :kind, Rescord.Lists.IdentifierKind do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
