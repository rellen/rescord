defmodule Rescord.Ruby.Settings do
  @moduledoc """
  How one organisation uses Ruby (ADR 0069): on or off, with which
  provider of the server, the place that an administrator agreed to, the
  allowance of a month, and the days that a conversation is kept. One row
  in the schema of the organisation. An organisation with no row has Ruby
  off.

  It has no secret, so it is a resource as each other (ADR 0068):
  temporal, with a paper trail. The history says who turned Ruby on, and
  which place they agreed to.

  A member with the power `settings` reads and changes it. No role reads
  it by default: `Rescord.Ruby.available?/2` reads it inside the domain.

  ## The agreement to a place

  With Ruby on, the records that a question needs leave the server for
  the provider. So the row keeps the place that an administrator agreed
  to: `agreed_destination`, a short key that code compares, and
  `agreed_words`, the sentence of that place for the history. An action
  that turns Ruby on takes the key of the place that the page showed, and
  refuses when the provider has another place by then
  (`Rescord.Ruby.Changes.Agree`).

  A root user who changes the service, the address or the region of a
  provider changes its key. No row of an organisation is written then: the
  two keys differ, so Ruby is off for the organisation until an
  administrator reads the new place and agrees.
  """

  # No action removes the row, so it needs no mark of a removal.
  use Rescord.Resource,
    domain: Rescord.Ruby,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Ruby.Changes

  @type t :: %__MODULE__{}

  # What an administrator sets. No action takes the agreement as input:
  # `Agree` writes it.
  @fields [:enabled, :provider_id, :allowance, :member_allowance, :retention_days]

  postgres do
    table "ruby_settings"
  end

  actions do
    defaults [:read]

    create :set do
      description "The first settings of the organisation"
      accept @fields
      argument :agreed_to, :string
      change Changes.Agree
    end

    update :change do
      require_atomic? false
      accept @fields
      argument :agreed_to, :string
      change Changes.Agree
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

    # Each row has the same value here, so the identity allows one row.
    attribute :which, :atom do
      allow_nil? false
      default :settings
      writable? false
      constraints one_of: [:settings]
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether Ruby answers the members of the organisation"
    end

    attribute :agreed_destination, :string do
      public? true
      writable? false
      description "The place that an administrator agreed to, as the key that code compares"
    end

    attribute :agreed_words, :string do
      public? true
      writable? false
      description "The sentence of that place, as it was at the agreement"
    end

    attribute :agreed_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    attribute :allowance, :integer do
      public? true
      constraints min: 0, max: 10_000_000
      description "Whole US cents for a month. It starts at the default of the provider"
    end

    attribute :member_allowance, :integer do
      public? true
      constraints min: 0, max: 10_000_000

      description "Whole US cents for a month that one member can use (ADR 0117). None: one member can use the whole allowance"
    end

    attribute :retention_days, :integer do
      allow_nil? false
      default 90
      public? true
      constraints min: 1, max: 3_650
      description "The days that a conversation is kept after its newest message"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :provider, Rescord.Ruby.Provider do
      public? true
      attribute_writable? true
      # From a temporal resource to one that is not.
      temporal_keys {:valid_at, nil}
    end
  end

  identities do
    identity :one_row, [:which]
  end
end
