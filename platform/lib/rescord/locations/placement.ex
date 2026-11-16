defmodule Rescord.Locations.Placement do
  @moduledoc """
  A resident or a group lives in a location for a time (`docs/domain.md`,
  section 5.5). A placement names a resident or a group, and never both.

  The period of the record is the time in the location. A move is a new
  version with another location, so a read as of a past instant gives where
  the resident or the group was. A resident and a group each have one
  placement at a time.

  A resident in a group that has a placement lives with its group. A
  placement of its own wins while it lasts, for example a week in a house
  for recovery (ADR 0029).
  """

  use Rescord.Resource,
    domain: Rescord.Locations,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "placements"

    check_constraints do
      check_constraint :resident_id, "one_subject",
        check: "(resident_id IS NULL) <> (group_id IS NULL)",
        message: "must name a resident or a group, and not both"
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :place do
      accept [:location_id, :resident_id, :group_id]
    end

    update :move do
      accept [:location_id]
    end

    destroy :finish
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :location, Rescord.Locations.Location do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :resident, Rescord.Residents.Resident do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :group, Rescord.Residents.Group do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_resident, [:resident_id], message: "has a placement already"
    identity :unique_group, [:group_id], message: "has a placement already"
  end
end
