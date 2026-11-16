defmodule Rescord.Inventory.StockMovement do
  @moduledoc """
  A quantity of a lot came into a place, or went out of it
  (`docs/domain.md`, section 5.8, and ADR 0034). A member records each
  movement by hand.

  `quantity` is more than zero for a movement in, and less than zero for a
  movement out. No action takes it as it is: each action takes a quantity
  that is more than zero, or a count, and
  `Rescord.Inventory.Changes.RecordMovement` gives it its sign.

  The place is a location, or no location: an organisation with no housing
  on record keeps its stock in no place in particular.

  ## The level

  The level of a lot in a place is the sum of its movements there. A
  movement out is refused when it takes more than the level. A member who
  finds another number on the shelf records a count, and Rescord writes the
  difference.

  Nothing changes a movement, and nothing removes one. A movement that is
  wrong gets a second movement that corrects it.
  """

  use Rescord.Resource,
    domain: Rescord.Inventory,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Inventory.Changes.{MoveIn, RecordMovement}

  postgres do
    table "stock_movements"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :receive do
      description "More of a lot came into a place"
      accept [:lot_id, :location_id, :happened_at, :note]
      argument :quantity, :decimal, allow_nil?: false
      change {RecordMovement, kind: :received, direction: :in}
    end

    create :use do
      description "A member used a quantity of a lot from a place"
      accept [:lot_id, :location_id, :happened_at, :note]
      argument :quantity, :decimal, allow_nil?: false
      change {RecordMovement, kind: :used, direction: :out}
    end

    create :discard do
      description "A member threw out a quantity of a lot from a place"
      accept [:lot_id, :location_id, :happened_at, :note]
      argument :quantity, :decimal, allow_nil?: false
      change {RecordMovement, kind: :discarded, direction: :out}
    end

    create :count do
      description "A member counted a lot in a place. The movement is the difference from the level"
      accept [:lot_id, :location_id, :happened_at, :note]
      argument :counted, :decimal, allow_nil?: false
      change {RecordMovement, kind: :counted, direction: :count}
    end

    create :move do
      description "A member moved a quantity of a lot from a place to another: this movement is out"
      accept [:lot_id, :location_id, :happened_at, :note]
      argument :quantity, :decimal, allow_nil?: false
      argument :to_location_id, :uuid
      change {RecordMovement, kind: :moved, direction: :out}
      change MoveIn
    end

    create :move_in do
      description "The movement in of a move. `MoveIn` runs this, and no role has a grant for it"
      accept [:lot_id, :location_id, :happened_at, :note]
      argument :quantity, :decimal, allow_nil?: false
      change {RecordMovement, kind: :moved, direction: :in}
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

    attribute :kind, Rescord.Inventory.MovementKind do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :quantity, :decimal do
      allow_nil? false
      public? true
      writable? false
      description "More than zero for a movement in, and less than zero for a movement out"
    end

    attribute :happened_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When the movement happened. The time of the write, when the member gives none"
    end

    attribute :note, :string do
      public? true
      constraints max_length: 500
    end

    # The id of the user who recorded the movement. It is a plain attribute:
    # a user is not temporal, so the database can hold no key from here.
    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end
  end

  relationships do
    belongs_to :lot, Rescord.Inventory.Lot do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :location, Rescord.Locations.Location do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
