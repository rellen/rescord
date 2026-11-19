defmodule Rescord.Transfers.Partnership do
  @moduledoc """
  Two refuges that agree to transfer residents to each other (ADR 0042).

  An administrator of one refuge asks another refuge by its short name, and
  the two are partners when an administrator of the other refuge accepts.
  No member sees a list of the other refuges: a person names a refuge that
  they know. Either refuge ends the partnership.

  ## States

      asked --accept--> accepted --end--> ended
      asked --decline-> declined
      asked --end-----> ended

  Two refuges have one partnership that is asked or accepted at a time.
  The record is outside the schemas of the two organisations, with the
  organisations. The "administrator" here is each role with the power
  `:transfers`.
  """

  use Rescord.Resource,
    domain: Rescord.Transfers,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Transfers.{Changes, Checks, Validations}

  postgres do
    table "partnerships"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :ask do
      description "Asks a refuge, by its short name, to be a partner"
      accept []
      argument :organisation_id, :uuid, allow_nil?: false
      argument :short_name, :string, allow_nil?: false
      change Changes.AskPartner
      validate Validations.NoOpenPartnership, before_action?: true
    end

    update :accept do
      accept []
      require_atomic? false
      change filter(expr(state == :asked))
      change set_attribute(:state, :accepted)
      change Changes.Answer
    end

    update :decline do
      accept []
      require_atomic? false
      change filter(expr(state == :asked))
      change set_attribute(:state, :declined)
      change Changes.Answer
    end

    update :end do
      description "Ends the partnership. Each transfer that it made stays"
      accept []
      require_atomic? false
      change filter(expr(state in [:asked, :accepted]))
      change set_attribute(:state, :ended)
      change Changes.Answer
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Checks.MemberOf
    end

    policy action(:ask) do
      authorize_if {Checks.PowerIn, side: :from}
    end

    policy action([:accept, :decline]) do
      authorize_if {Checks.PowerIn, side: :to}
    end

    policy action(:end) do
      authorize_if {Checks.PowerIn, side: :either}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :from_organisation_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The refuge that asked"
    end

    attribute :to_organisation_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The refuge that answers"
    end

    attribute :state, :atom do
      allow_nil? false
      default :asked
      public? true
      writable? false
      constraints one_of: [:asked, :accepted, :declined, :ended]
    end

    attribute :asked_by_id, :uuid, public?: true, writable?: false
    attribute :answered_by_id, :uuid, public?: true, writable?: false
    attribute :answered_at, :utc_datetime_usec, public?: true, writable?: false

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :from_organisation, Rescord.Accounts.Organisation do
      public? true
      define_attribute? false
      source_attribute :from_organisation_id
    end

    belongs_to :to_organisation, Rescord.Accounts.Organisation do
      public? true
      define_attribute? false
      source_attribute :to_organisation_id
    end
  end
end
