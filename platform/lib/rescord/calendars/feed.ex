defmodule Rescord.Calendars.Feed do
  @moduledoc """
  A calendar feed of one member (ADR 0074): an address that a calendar app
  reads, and what the calendar at that address holds.

  ## The parts

  A member chooses the parts of the feed when they make it:

    * `tasks` - `:mine`, the tasks that name the member; `:mine_and_open`,
      those and the tasks for each member; `:all`, each task; or `:none`;
    * `with_returns` - the days on which residents that are away are
      expected back;
    * `with_expiry` - the expiry dates of the stock;
    * `with_notes` - also the words that a person wrote: the note of a
      task, the reason of an absence. A calendar service keeps a copy of
      the feed, so this is `false` at first.

  ## The owner

  A feed belongs to one member, in `member_id`, and `owner_id` is the user
  of that member. No action takes either as input: `subscribe` reads the
  member of the actor. A feed reads the records as its owner, so the
  policies decide what it holds. A removed member is archived, and a later
  invitation makes a new member: the feeds of the old one stay dead.

  ## The token

  The address of a feed holds a token (`Rescord.Calendars.Token`). This
  resource stores only `token_hash`. `subscribe` returns the token one
  time, in the metadata `:token` of the feed. `revoke` empties the hash and
  archives the row, so nothing reads the feed again.

  ## Not temporal

  A history row of a temporal resource would keep each old hash, and the
  mark `last_fetched_at` moves each hour. So this resource is not temporal.
  Its history is in its paper trail, which holds neither the hash nor the
  moves of the mark.
  """

  use Rescord.Resource,
    domain: Rescord.Calendars,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Calendars.{Changes, Validations}

  postgres do
    table "calendar_feeds"

    # A request of a calendar app finds its feed by the hash of its token.
    custom_indexes do
      index [:token_hash], unique: true
      index [:member_id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    ignore_attributes [:token_hash, :last_fetched_at]
    # This one moves the mark only, when a calendar app reads the feed.
    ignore_actions [:mark]
  end

  actions do
    defaults [:read]

    create :subscribe do
      description "Makes a feed of the member of the actor, with a new token in the metadata `:token`"
      accept [:name, :tasks, :with_returns, :with_expiry, :with_notes]
      validate Validations.HasAPart
      change Changes.NewToken
    end

    update :mark do
      description "Says when a calendar app last read the feed. Rescord runs this, and no role has a grant for it"
      accept []
      argument :at, :utc_datetime, allow_nil?: false
      change set_attribute(:last_fetched_at, arg(:at))
    end

    destroy :revoke do
      description "Ends the feed: its address reads nothing from then on. The row and its history stay"
      change set_attribute(:token_hash, nil)
    end

    read :of_user do
      description "The feeds of a user in the organisation"
      argument :user_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:user_id))
      pagination keyset?: true, required?: false
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      # The removal of a member is the decision (ADR 0105).
      authorize_if signal_in(Rescord.Accounts.Signals, :member_removed)
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 60
      description "What the person calls the feed, such as the device that reads it"
    end

    attribute :tasks, :atom do
      allow_nil? false
      default :mine
      public? true
      constraints one_of: [:none, :mine, :mine_and_open, :all]
    end

    attribute :with_returns, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :with_expiry, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :with_notes, :boolean do
      allow_nil? false
      default false
      public? true
    end

    # The owner decides who reads the feed, so no action takes it as input.
    attribute :member_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :owner_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The user of the member. The scope `own` of a grant reads it"
    end

    attribute :token_hash, :string do
      public? false
      sensitive? true
      writable? false
      description "The SHA-256 hash of the token of the address. Empty after `revoke`"
    end

    attribute :last_fetched_at, :utc_datetime do
      public? true
      writable? false
      description "When a calendar app last read the feed, to the hour"
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :member, Rescord.Accounts.Member do
      public? true
      define_attribute? false
      source_attribute :member_id
    end
  end

  # The feeds of a member who was taken out of the organisation are revoked,
  # so that nothing waits for a read of the member to fail (ADR 0105).
  signals_in do
    from Rescord.Accounts.Signals do
      on :member_removed, :revoke_of_removed_member,
        action: :revoke,
        read_action: :of_user,
        args: [:user_id]
    end
  end
end
