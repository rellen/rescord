defmodule Rescord.Locations.LocationParent do
  @moduledoc """
  The tie that says which location contains a location (`docs/domain.md`,
  section 5.5). A location is inside one other location, or inside none.

  A location does not contain itself, directly or through other locations.
  The period of the tie is the time that the location was there, so a read
  as of a past instant gives the housing as it was.
  """

  use Rescord.Resource,
    domain: Rescord.Locations,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "location_parents"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :put_inside do
      accept [:location_id, :parent_id]
      validate Rescord.Locations.Validations.NotInsideItself
    end

    destroy :take_out
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

    belongs_to :parent, Rescord.Locations.Location do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_location, [:location_id], message: "is inside a location already"
  end
end
