defmodule Rescord.Locations.Location do
  @moduledoc """
  A place where a resident lives, or where the organisation keeps a thing
  (`docs/domain.md`, section 5.5).

  Each organisation defines its own kinds of location, and a location can be
  inside any other location: `Rescord.Locations.LocationParent` is the tie.
  The model thus fits each organisation, and a change to its housing needs
  no migration.

  A location can have a capacity, the number of residents that it houses. A
  placement over the capacity is permitted, and a page says so.

  An organisation closes a location that it uses no more. That archives it.
  """

  use Rescord.Resource,
    domain: Rescord.Locations,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "locations"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :add do
      description "Adds a location, inside another one when `parent_id` names it"
      accept [:name, :kind_id, :capacity]
      argument :parent_id, :uuid
      change Rescord.Locations.Changes.PutInside
    end

    update :revise do
      accept [:name, :kind_id, :capacity]
    end

    destroy :close do
      description "Closes a location that the organisation uses no more. The row and its history stay"
      require_atomic? false
      validate Rescord.Locations.Validations.IsEmpty, before_action?: true
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

    attribute :capacity, :integer do
      public? true
      constraints min: 1

      description "The number of residents that the location houses, when the organisation gives one"
    end
  end

  relationships do
    belongs_to :kind, Rescord.Lists.LocationKind do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :parent_tie, Rescord.Locations.LocationParent do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :placements, Rescord.Locations.Placement do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
