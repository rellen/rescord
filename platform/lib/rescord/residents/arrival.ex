defmodule Rescord.Residents.Arrival do
  @moduledoc """
  How and when a resident came to the organisation (`docs/domain.md`,
  section 5.2). A resident has one arrival or none: a resident with none is
  expected.

  An arrival is a fact that happened, so its date is not after today.
  """

  use Rescord.Residents.Fact, table: "arrivals"

  actions do
    defaults [:read]

    create :record do
      accept [:resident_id, :kind, :arrived_on, :note]
      validate {Rescord.Residents.Validations.NotAfterToday, attribute: :arrived_on}
    end

    update :correct do
      # The validation reads the date in Elixir.
      require_atomic? false
      accept [:kind, :arrived_on, :note]
      validate {Rescord.Residents.Validations.NotAfterToday, attribute: :arrived_on}
    end
  end

  attributes do
    attribute :kind, Rescord.Residents.ArrivalKind do
      allow_nil? false
      public? true
    end

    attribute :arrived_on, :date do
      allow_nil? false
      public? true
    end

    attribute :note, :string do
      public? true
      constraints max_length: 500
    end
  end

  identities do
    identity :unique_resident, [:resident_id], message: "has an arrival already"
  end
end
