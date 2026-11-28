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

  ## The reply

  `say` puts a job in the queue `ruby` of Oban, with the trigger `respond`
  of AshOban: the job holds the id of the message, the organisation and
  the id of the member, and no word of the message. It runs the action
  `respond` as that member (`Rescord.Ruby.ActorPersister`), which writes
  the reply (`Rescord.Ruby.Changes.Respond`). A job runs one time: the
  provider bills each try, so a reply that failed stays failed, and the
  member asks again.

  A message has one reply at most (the identity `one_reply`), and the
  trigger takes a message of a member that has none. So a job that runs a
  second time writes nothing.

  ## What `say` refuses

  Where Ruby is off for the person; while Ruby still answers in the
  conversation; past the allowance of the month; in a conversation that
  is full; and more than 6 messages of one person in a minute, or 120 in
  a day. `Rescord.Ruby.refusal/1` gives the reason of a refusal.

  `respond`, `open_reply`, `grow` and `close` are in no grant: the job and
  `Rescord.Ruby.Replies` run them. The bypass of the policy holds only
  inside a call that AshOban makes.

  Never log the text, the header or the parts of a message.
  """

  use Rescord.Resource,
    domain: Rescord.Ruby,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    extensions: [AshOban, AshRateLimiter],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Ruby.{Changes, Rating, Reason, ReplyState, Source, Validations}

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

  oban do
    triggers do
      trigger :respond do
        action :respond
        queue :ruby
        where expr(needs_reply)
        # No scheduler: `say` starts the job of its message.
        scheduler_cron false
        # The provider bills each try.
        max_attempts 1
        # The action runs for as long as the model writes, and holds no
        # transaction and no lock for that time.
        lock_for_update? false
        actor_persister Rescord.Ruby.ActorPersister
        # AshOban would write the error with its message. The lines of a
        # job that failed are those of `Rescord.Log.Jobs`.
        log_errors? false
        log_final_error? false
        worker_module_name Rescord.Ruby.Message.Workers.Respond
        scheduler_module_name Rescord.Ruby.Message.Schedulers.Respond
      end
    end
  end

  # How many messages one person says (ADR 0020): 6 a minute here, and 120
  # a day in the action itself, because the section takes one limit for an
  # action. The count is of this node, and a restart forgets it.
  rate_limit do
    backend Rescord.RateLimit
    action :say, limit: 6, per: :timer.minutes(1), key: &__MODULE__.minute_key/2
  end

  actions do
    defaults [:read]

    read :of_conversation do
      description "The messages of one conversation, in the order of the talk"
      argument :conversation_id, :uuid, allow_nil?: false
      filter expr(conversation_id == ^arg(:conversation_id))
      # The id of a message holds its time.
      prepare build(sort: [id: :asc])
    end

    create :say do
      description "The member says a thing to Ruby, in a conversation of their own. A job then writes the reply"
      accept [:conversation_id, :text]
      # Ruby is on here, for this person. No key is decrypted.
      validate Validations.RubyOn
      change Changes.SetOwner
      change Changes.Say

      change {AshRateLimiter.Change,
              limit: 120, per: :timer.hours(24), key: &__MODULE__.day_key/2}

      change run_oban_trigger(:respond)
    end

    update :respond do
      description "Writes the reply to this message. Only the job runs it"
      accept []
      require_atomic? false
      # The model writes for a long time: no transaction is open meanwhile.
      transaction? false
      change Changes.Respond
    end

    create :open_reply do
      description "Makes the reply to a message of a member, with no word yet. Only Ruby runs it"
      accept [:conversation_id]
      argument :owner_id, :uuid, allow_nil?: false
      argument :response_to_id, :uuid, allow_nil?: false
      change set_attribute(:owner_id, arg(:owner_id))
      change set_attribute(:response_to_id, arg(:response_to_id))
      change set_attribute(:source, :ruby)
      change set_attribute(:state, :streaming)
    end

    update :grow do
      description "Saves the words, the parts and the steps of a reply so far. Only Ruby runs it"
      accept [:text, :parts, :steps]
    end

    update :close do
      description "Writes the end of a reply: its words, its state and reason, the model, the tokens and their price. Only Ruby runs it"

      accept [
        :text,
        :parts,
        :steps,
        :state,
        :reason,
        :model,
        :usage,
        :cost_microdollars,
        :prompt_tokens,
        :prompt_fingerprint
      ]
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
    # AshOban asks the policy for the read and for the action of a trigger,
    # and `respond` is in no grant. This check is true only inside a call
    # that AshOban makes.
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

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
      # It ends with an empty line, which stays.
      constraints trim?: false

      description "For a message of a member: what the model gets before the text, and the page hides"
    end

    attribute :parts, {:array, :map} do
      allow_nil? false
      default []
      sensitive? true

      description "For a reply: its text, its tool calls and their results, as the model gets them again"
    end

    attribute :steps, {:array, :map} do
      allow_nil? false
      default []
      public? true
      sensitive? true

      description "For a reply: one step for each call of a tool, as `Rescord.Ruby.Steps` made it from the call. It holds no tool result"
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

    attribute :prompt_tokens, :integer do
      constraints min: 0

      description "For a reply: the tokens that the conversation holds after it, the prompt of its last request and what came after. The next request starts from them"
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

  calculations do
    # A message of a member needs a reply while it has none.
    calculate :needs_reply, :boolean, expr(source == :user and not exists(reply))
  end

  identities do
    # A message has one reply at most, so a second job makes no second one.
    identity :one_reply, [:response_to_id]
  end

  @doc false
  def minute_key(_changeset, context), do: person_key("minute", context)

  @doc false
  def day_key(_changeset, context), do: person_key("day", context)

  # One count for each person, in each organisation where they ask.
  defp person_key(span, %{actor: %{id: id}}) when is_binary(id),
    do: "ruby/say/#{span}/#{id}"

  defp person_key(span, _context), do: "ruby/say/#{span}/nobody"
end
