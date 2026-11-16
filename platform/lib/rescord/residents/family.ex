defmodule Rescord.Residents.Family do
  @moduledoc """
  A named set of residents that came together or were born together, for
  example a litter that arrived with no known parent (`docs/domain.md`,
  section 5.3). `Rescord.Residents.FamilyMember` ties a resident to it.
  """

  use Rescord.Resource,
    domain: Rescord.Residents,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "families"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :name do
      accept [:name]
    end

    update :rename do
      accept [:name]
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
  end

  relationships do
    has_many :members, Rescord.Residents.FamilyMember do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  identities do
    identity :unique_name, [:name], message: "is the name of a family already"
  end
end
