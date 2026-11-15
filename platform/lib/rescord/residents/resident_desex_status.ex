defmodule Rescord.Residents.ResidentDesexStatus do
  @moduledoc """
  Whether a resident is desexed, in a table of its own (`docs/domain.md`,
  design rule 2). A change is a new version, so the history says when Rescord
  learned it.

  `Rescord.Residents.Resident` writes the status: no page calls these actions.
  """

  use Rescord.Residents.Fact, table: "resident_desex_statuses"

  actions do
    defaults [:read]

    create :set do
      accept [:resident_id, :status]
    end

    update :change do
      accept [:status]
    end
  end

  attributes do
    attribute :status, Rescord.Residents.DesexStatus do
      allow_nil? false
      default :unknown
      public? true
    end
  end

  identities do
    identity :unique_resident, [:resident_id]
  end
end
