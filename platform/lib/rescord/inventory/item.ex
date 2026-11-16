defmodule Rescord.Inventory.Item do
  @moduledoc """
  One thing that an organisation keeps a supply of: a food, a medication, a
  kind of bedding (`docs/domain.md`, section 5.8, and ADR 0034).

  An item has a category and a unit, each from a list that the organisation
  can extend. Its stock is in its lots (`Rescord.Inventory.Lot`). Rescord
  stores no level: `Rescord.Inventory.stock/1` calculates it from the stock
  movements.

  `reorder_level` is the quantity in the whole organisation below which the
  organisation orders more. `Rescord.Inventory.ReorderLevel` holds the same
  for one location.
  """

  use Rescord.Resource,
    domain: Rescord.Inventory,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "items"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :add do
      accept [:name, :category_id, :unit_id, :reorder_level, :note]
    end

    update :revise do
      accept [:name, :category_id, :unit_id, :reorder_level, :note]
    end

    destroy :remove do
      description "Removes an item that the organisation keeps no more. The row and its history stay"
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

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80
    end

    attribute :reorder_level, :decimal do
      public? true
      constraints min: 0

      description "The quantity in the whole organisation below which the organisation orders more"
    end

    attribute :note, :string do
      public? true
      constraints max_length: 1000
    end
  end

  relationships do
    belongs_to :category, Rescord.Lists.ItemCategory do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :unit, Rescord.Lists.Unit do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :lots, Rescord.Inventory.Lot do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
