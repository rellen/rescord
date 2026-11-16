defmodule Rescord.Residents.FamilyMember do
  @moduledoc "A resident in a family. A resident is in a family one time."

  use Rescord.Residents.Fact, table: "family_members", archive?: false

  actions do
    defaults [:read]

    create :add do
      accept [:resident_id, :family_id]
    end

    destroy :remove
  end

  relationships do
    belongs_to :family, Rescord.Residents.Family do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_member, [:resident_id, :family_id], message: "is in this family already"
  end
end
