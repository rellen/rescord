defmodule Rescord.Residents.Departure do
  @moduledoc """
  How, when and why a resident left the organisation (`docs/domain.md`,
  section 5.2). A resident with a departure has left.

  A departure is a fact that happened, so its date is not after today. A
  member withdraws a departure that was a mistake. The withdrawal ends its
  period, so the resident can leave again later.
  """

  use Rescord.Residents.Fact, table: "departures", archive?: false

  actions do
    defaults [:read]

    create :record do
      accept [:resident_id, :kind, :departed_on, :note]
      validate {Rescord.Residents.Validations.NotAfterToday, attribute: :departed_on}
    end

    update :correct do
      # The validation reads the date in Elixir.
      require_atomic? false
      accept [:kind, :departed_on, :note]
      validate {Rescord.Residents.Validations.NotAfterToday, attribute: :departed_on}
    end

    destroy :withdraw
  end

  attributes do
    attribute :kind, Rescord.Residents.DepartureKind do
      allow_nil? false
      public? true
    end

    attribute :departed_on, :date do
      allow_nil? false
      public? true
    end

    attribute :note, :string do
      public? true
      constraints max_length: 500
    end
  end

  identities do
    identity :unique_resident, [:resident_id], message: "has a departure already"
  end
end
