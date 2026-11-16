defmodule Rescord.Residents.ParentLink do
  @moduledoc """
  One resident is the mother or the father of another (`docs/domain.md`,
  section 5.3). The resident of the link is the young, and `parent` is the
  parent. Both are residents of the organisation: a parent that did not live
  there is a resident with no arrival.

  Rescord stores no other relation. It calculates a sibling, and the words
  for a group, from these links (`Rescord.Residents.Kinship`).

  A resident has one mother and one father at most. A resident is not its
  own parent, and not a parent of one of its own parents.
  """

  use Rescord.Residents.Fact, table: "parent_links", archive?: false

  actions do
    defaults [:read]

    create :record do
      accept [:resident_id, :parent_id, :role]
      validate Rescord.Residents.Validations.ParentIsNotYoung
    end

    destroy :remove
  end

  attributes do
    attribute :role, Rescord.Residents.KinRole do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :parent, Rescord.Residents.Resident do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_role, [:resident_id, :role], message: "has a parent in this role already"
  end
end
