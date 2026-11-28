defmodule Rescord.Ruby.Message do
  @moduledoc """
  One message of a conversation with Ruby (ADR 0069): what the member
  said, or a reply of Ruby. A reply holds its tool calls and their results
  in `parts`, so a conversation holds copies of what the tools read. That
  is why it is kept for a number of days and then deleted for real, and
  why it is not in the export.

  A message has the owner of its conversation. `say` takes the owner from
  the actor and refuses a conversation of another person, so the grant of
  a member is a filter on one column.

  The actions of the job that writes a reply come with that job.

  Never log the text, the header or the parts of a message.
  """

  use Rescord.Resource,
    domain: Rescord.Ruby,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Ruby.{Changes, Rating, Reason, ReplyState, Source}

  @type t :: %__MODULE__{}

  postgres do
    table "ruby_messages"

    references do
      reference :conversation, on_delete: :delete
      reference :response_to, on_delete: :delete
    end

    custom_indexes do
      index [:conversation_id, :id]
    end
  end

  actions do
    defaults [:read]

    create :say do
      description "The member says a thing to Ruby, in a conversation of their own"
      accept [:conversation_id, :text]
      change Changes.SetOwner
      change Changes.Say
    end

    update :rate do
      description "The member says whether a reply helped"
      accept [:rating, :rating_note]
      validate attribute_equals(:source, :ruby), message: "only a reply has a rating"
    end

    update :stop do
      description "The member stops the reply to this message. It works before the reply exists"
      accept []
      validate attribute_equals(:source, :user), message: "only a message of a member has a reply"
      change set_attribute(:stop_requested, true)
    end
  end

  policies do
    # No bypass for a root user (ADR 0069).
    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :owner_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The user of the conversation. An action sets it"
    end

    attribute :source, Source do
      allow_nil? false
      public? true
      writable? false
    end

    # No maximum here: a reply can be long. `say` holds what a member
    # typed to its limit.
    attribute :text, :string do
      allow_nil? false
      default ""
      public? true
      sensitive? true
      constraints trim?: false, allow_empty?: true
      description "What the page shows. For a reply that is not complete, the text so far"
    end

    attribute :header, :string do
      sensitive? true

      description "For a message of a member: what the model gets before the text, and the page hides"
    end

    attribute :parts, {:array, :map} do
      allow_nil? false
      default []
      sensitive? true

      description "For a reply: its text, its tool calls and their results, as the model gets them again"
    end

    attribute :prompt_fingerprint, :string do
      description "For a reply: a hash of the prompt and the tools that made it"
    end

    attribute :state, ReplyState do
      public? true
      description "For a reply: where it stands"
    end

    attribute :reason, :atom do
      public? true
      constraints one_of: Reason.all()
      description "For a reply: why it failed, or that the limit of an answer cut it"
    end

    attribute :resume_requested, :boolean do
      allow_nil? false
      default false
      description "For a message of a member: its reply waited for a proposal, and can go on"
    end

    attribute :stop_requested, :boolean do
      allow_nil? false
      default false
      description "For a message of a member: the member stopped its reply"
    end

    attribute :model, :string do
      description "For a reply: the model that answered"
    end

    attribute :usage, :map do
      description "For a reply: its tokens, as `input`, `cache_read`, `cache_write` and `output`"
    end

    attribute :cost_microdollars, :integer do
      constraints min: 0
      description "For a reply: the price of its tokens, in millionths of a US dollar"
    end

    attribute :rating, Rating do
      public? true
    end

    attribute :rating_note, :string do
      public? true
      sensitive? true
      constraints max_length: 500
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :conversation, Rescord.Ruby.Conversation do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :response_to, __MODULE__ do
      description "For a reply: the message of the member that it answers"
    end

    has_one :reply, __MODULE__ do
      destination_attribute :response_to_id
    end
  end

  identities do
    # A message has one reply at most, so a second job makes no second one.
    identity :one_reply, [:response_to_id]
  end
end
