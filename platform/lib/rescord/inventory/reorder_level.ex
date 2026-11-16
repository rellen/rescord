defmodule Rescord.Inventory.ReorderLevel do
  @moduledoc """
  The quantity of an item in one location below which the organisation
  orders more, or brings more from another place (`docs/domain.md`,
  section 5.8). The level for the whole organisation is `reorder_level` of
  the item.

  An item has one such level in a location at a time. The removal of a
  level ends its period, so the same location can get a level again.
  """

  use Rescord.Resource,
    domain: Rescord.Inventory,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "reorder_levels"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :set do
      accept [:item_id, :location_id, :quantity]
    end

    update :change do
      accept [:quantity]
    end

    destroy :clear
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

    attribute :quantity, :decimal do
      allow_nil? false
      public? true
      constraints greater_than: 0
    end
  end

  relationships do
    belongs_to :item, Rescord.Inventory.Item do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :location, Rescord.Locations.Location do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_place, [:item_id, :location_id], message: "has a reorder level there already"
  end
end
