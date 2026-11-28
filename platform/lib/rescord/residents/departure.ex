defmodule Rescord.Residents.Departure do
  @moduledoc """
  How, when and why a resident left the organisation (`docs/domain.md`,
  section 5.2). A resident with a departure has left.

  A departure is a fact that happened, so its date is not after today. A
  member withdraws a departure that was a mistake. The withdrawal ends its
  period, so the resident can leave again later.

  A new departure emits `:resident_departed` (ADR 0067): the locations end
  the placement of the resident, and the tasks take the resident out of the
  routines and out of the tasks that are due. A withdrawal restores none of
  that.
  """

  use Rescord.Residents.Fact, table: "departures", archive?: false

  actions do
    defaults [:read]

    create :record do
      accept [:resident_id, :kind, :departed_on, :note]
      validate {Rescord.Residents.Validations.NotAfterToday, attribute: :departed_on}

      emit Rescord.Residents.Signals, :resident_departed, fields: [resident_id: :resident_id]
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
