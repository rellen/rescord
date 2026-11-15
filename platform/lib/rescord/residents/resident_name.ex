defmodule Rescord.Residents.ResidentName do
  @moduledoc """
  The name of a resident, in a table of its own (`docs/domain.md`, design
  rule 2). A new name is a new version, so a read as of a past instant gives
  the name that the resident had then.

  A resident with no name has no row here. `Rescord.Residents.Resident`
  writes the name: no page calls these actions.
  """

  use Rescord.Residents.Fact, table: "resident_names"

  actions do
    defaults [:read]

    create :set do
      accept [:resident_id, :name]
    end

    update :change do
      accept [:name]
    end
  end

  attributes do
    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80
    end
  end

  identities do
    identity :unique_resident, [:resident_id]
  end
end
