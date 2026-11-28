defmodule Rescord.Ruby.Conversation do
  @moduledoc """
  A conversation of one member with Ruby (ADR 0069), in the schema of the
  organisation.

  It belongs to the member who started it: no action takes the owner as
  input. The member reads, names and removes it. A member with the power
  `settings` reads each conversation of the organisation, and changes
  none. No other member reads it, and the policy has no bypass for a root
  user: an operator who is no member of the rescue reads nothing here.

  It is the working notes of one person, so it is deleted for real, with
  its messages: it is not temporal, keeps no paper trail and is not
  archived. That is the exception to design rule 9 that ADR 0069 states.
  """

  use Rescord.Resource,
    domain: Rescord.Ruby,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Ruby.Changes

  @type t :: %__MODULE__{}

  postgres do
    table "ruby_conversations"

    custom_indexes do
      # The list of a member, the newest first.
      index [:owner_id, :last_message_at]
    end
  end

  actions do
    defaults [:read]

    # The read of the pages of the member. The filter is in the action, and
    # not only in the grant: a member with the power `settings` reads each
    # conversation through `read`, and this list still holds their own.
    read :mine do
      description "The conversations of the actor, the newest first"
      filter expr(owner_id == ^actor(:id))
      prepare build(sort: [last_message_at: :desc, id: :desc])
      # "Your conversations" pages it by number, with the count of pages.
      pagination offset?: true, keyset?: true, countable: true, required?: false
    end

    read :of_member do
      description "The conversations of one member, for a person with the power `settings`"
      argument :owner_id, :uuid, allow_nil?: false
      filter expr(owner_id == ^arg(:owner_id))
      prepare build(sort: [last_message_at: :desc, id: :desc])
    end

    create :start do
      description "The actor starts a conversation"
      accept [:about]
      change Changes.SetOwner
      change set_attribute(:last_message_at, &DateTime.utc_now/0)
    end

    update :rename do
      accept [:title]
      validate present(:title), message: "give the conversation a name"
    end

    update :touch do
      description "Writes the time of the newest message, and the first title. Only Ruby runs it"
      accept [:title, :last_message_at]
    end

    # The messages go with it in the database: their reference has
    # `on_delete: :delete`. So one statement deletes all, and a fault in
    # the middle leaves no row of the conversation.
    destroy :remove do
      description "Deletes the conversation for real, with its messages"
    end
  end

  policies do
    # No bypass for a root user (ADR 0069).
    policy always() do
      # The erasure of the person on request is the decision (ADR 0105).
      authorize_if signal_in(Rescord.Accounts.Signals, :member_erased)
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :owner_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The user whose conversation it is. An action sets it from the actor"
    end

    attribute :title, :string do
      public? true
      sensitive? true
      constraints max_length: 120
      description "The first words of the first message, or the name that the member gave"
    end

    attribute :about, :string do
      public? true
      constraints max_length: 60, match: ~r/\A[a-z_]+:[0-9a-f-]{36}\z/
      description "The record that the member opened Ruby from, such as `resident:<id>`"
    end

    attribute :last_message_at, :utc_datetime_usec do
      allow_nil? false
      public? true

      description "When the newest message came: the order of the list, and the start of the days that it is kept"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :messages, Rescord.Ruby.Message do
      # The id of a message holds its time, so this is the order of the talk.
      sort id: :asc
    end
  end

  # The conversations of a person erased on request are their own words,
  # and go with their messages (ADR 0105). The rows of `Rescord.Ruby.Usage`
  # stay for the costs: they name the user id, whose account names nobody
  # once it is erased.
  signals_in do
    from Rescord.Accounts.Signals do
      on :member_erased, :remove_of_erased_member,
        action: :remove,
        get_by: [owner_id: :user_id]
    end
  end

  aggregates do
    count :message_count, :messages do
      public? true
      description "How many messages the conversation holds, of the member and of Ruby"
    end
  end
end
