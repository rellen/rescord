defmodule Rescord.Inventory.Supplier do
  @moduledoc """
  A shop, a clinic or a person that an organisation gets its supplies from
  (`docs/domain.md`, section 5.8). A lot can name its supplier.
  """

  use Rescord.Resource,
    domain: Rescord.Inventory,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "suppliers"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :add do
      accept [:name, :contact, :note]
    end

    update :revise do
      accept [:name, :contact, :note]
    end

    destroy :remove do
      description "Removes a supplier that the organisation uses no more. The row and its history stay"
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
      constraints min_length: 1, max_length: 120
    end

    attribute :contact, :string do
      public? true
      constraints max_length: 500
      description "How to reach the supplier: a telephone number, an address, a person"
    end

    attribute :note, :string do
      public? true
      constraints max_length: 1000
    end
  end
end
