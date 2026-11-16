defmodule Rescord.Inventory.Lot do
  @moduledoc """
  One delivery of an item: what came at one time, with one expiry date
  (`docs/domain.md`, section 5.8, and ADR 0034). The maintainer answered
  that Rescord tracks the inventory by lot, with an expiry date, and by
  location.

  A member makes a lot when its first stock comes: `receive` takes the
  quantity and the place, and writes the first stock movement in the same
  transaction. The level of a lot in each place is the sum of its stock
  movements. Nothing removes a lot: a lot with nothing left is history.
  """

  use Rescord.Resource,
    domain: Rescord.Inventory,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "lots"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :receive do
      description "Makes a lot of an item with its first stock"
      accept [:item_id, :supplier_id, :code, :expires_on, :note]

      argument :quantity, :decimal, allow_nil?: false
      argument :location_id, :uuid
      argument :happened_at, :utc_datetime_usec

      change Rescord.Inventory.Changes.FirstStock
    end

    update :revise do
      description "Corrects the facts of a lot"
      accept [:supplier_id, :code, :expires_on, :note]
    end
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

    attribute :code, :string do
      public? true
      constraints max_length: 60
      description "The words on the pack that name the lot, when it has some"
    end

    attribute :expires_on, :date, public?: true

    attribute :note, :string do
      public? true
      constraints max_length: 1000
    end
  end

  relationships do
    belongs_to :item, Rescord.Inventory.Item do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :supplier, Rescord.Inventory.Supplier do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :movements, Rescord.Inventory.StockMovement do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
