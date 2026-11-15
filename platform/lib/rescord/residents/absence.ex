defmodule Rescord.Residents.Absence do
  @moduledoc """
  A time for which a resident is away, for example at a clinic. It is the one
  value of the status that a member sets (`docs/domain.md`, section 5.2).

  The period of the record is the time away: it starts when a member says
  that the resident is away, and it ends when a member says that the resident
  is back. A read as of an instant inside the period finds the absence, and a
  read after it finds none.
  """

  use Rescord.Residents.Fact, table: "absences", archive?: false

  actions do
    defaults [:read]

    create :start do
      accept [:resident_id, :reason, :expected_back_on]
    end

    destroy :finish
  end

  attributes do
    attribute :reason, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 200
    end

    attribute :expected_back_on, :date do
      public? true
    end
  end

  identities do
    identity :unique_resident, [:resident_id], message: "is away already"
  end
end
