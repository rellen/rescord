defmodule Rescord.Ruby.Usage do
  @moduledoc """
  What an organisation used of the assistant (ADR 0069): one row for a
  member, a day and a model, with counts and no word of a conversation.

  The use of a month is the sum of these rows, and not a sum over the
  replies: a conversation is deleted for real, with its replies, and what
  it cost stays owed. So the rows stay when a conversation goes, and when
  a member goes: a row then has an id that names nobody.

  The day is a day of UTC, as the provider bills. The job of a reply adds
  to the row of today after each reply that sent a request, whatever its
  end: a reply that failed or that the member stopped is billed too.

  A person whose role has the power `settings` reads the rows, for the
  use of the month on the settings page. `add` is in no grant: the job
  runs it.
  """

  use Rescord.Resource,
    domain: Rescord.Ruby,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  # What a reply adds to. Each is a whole number that only grows.
  @counts [
    :replies,
    :requests,
    :input_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :output_tokens,
    :cost_microdollars,
    :failed,
    :refused,
    :stopped
  ]

  @doc "The counts of a row, in order."
  @spec counts() :: [atom]
  def counts, do: @counts

  postgres do
    table "ruby_usage"
  end

  actions do
    defaults [:read]

    create :add do
      description "Adds the counts of one reply to the row of its member, day and model. Only Ruby runs it"
      accept [:day, :user_id, :model] ++ @counts
      upsert? true
      upsert_identity :row
      # A row that is there gets each count added to its own.
      change Rescord.Ruby.Changes.AddCounts
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    # The power `settings`, from `Rescord.Ruby.Grants`.
    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :day, :date do
      allow_nil? false
      public? true
      description "A day of UTC, as the provider bills"
    end

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      description "The member who asked. The row stays when the member goes"
    end

    attribute :model, :string do
      allow_nil? false
      public? true
    end

    for count <- @counts do
      attribute count, :integer do
        allow_nil? false
        default 0
        public? true
        constraints min: 0
      end
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :row, [:day, :user_id, :model]
  end
end
