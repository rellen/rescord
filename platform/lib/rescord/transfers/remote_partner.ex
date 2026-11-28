defmodule Rescord.Transfers.RemotePartner do
  @moduledoc """
  A partner refuge on another Rescord server (ADR 0043): its id and its
  name there, and the two public keys of its partner card
  (`Rescord.Transfers.Keys`).

  An administrator records it from the card that the other refuge gave,
  after the two read the fingerprint to each other. A transfer file opens
  only when it comes from a partner that this refuge recorded and has not
  ended, and only with that partner's key. Here, an administrator is each
  role with the power `:transfers`.
  """

  use Rescord.Resource,
    domain: Rescord.Transfers,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Transfers.{Changes, Checks, Validations}

  postgres do
    table "remote_partners"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # The keys are bytes, which JSON does not hold: the fingerprint names them.
    ignore_attributes [:sign_public, :box_public]
  end

  actions do
    defaults [:read]

    create :record do
      description "Records a refuge on another server from its partner card"
      accept []
      argument :organisation_id, :uuid, allow_nil?: false
      argument :card, :string, allow_nil?: false, constraints: [max_length: 2000]
      change Changes.RecordCard
      validate Validations.NewRemotePartner, before_action?: true
    end

    update :end do
      description "Ends the partnership. A file from this refuge does not open after it"
      accept []
      require_atomic? false
      change filter(expr(state == :active))
      change set_attribute(:state, :ended)
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Checks.MemberOf
    end

    policy action([:record, :end]) do
      authorize_if {Checks.PowerIn, side: :own}
    end
  end

  # A page of the refuge hears of it (ADR 0096).
  pub_sub do
    publish_all :create, [:organisation_id, "transfers"]
    publish_all :update, [:organisation_id, "transfers"]
    publish_all :destroy, [:organisation_id, "transfers"]
  end

  attributes do
    uuid_primary_key :id

    attribute :organisation_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The refuge of this server that recorded the partner"
    end

    attribute :refuge_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The id of the partner on its own server"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      writable? false
    end

    attribute :sign_public, :binary, allow_nil?: false, public?: true, writable?: false
    attribute :box_public, :binary, allow_nil?: false, public?: true, writable?: false
    attribute :fingerprint, :string, allow_nil?: false, public?: true, writable?: false

    attribute :state, :atom do
      allow_nil? false
      default :active
      public? true
      writable? false
      constraints one_of: [:active, :ended]
    end

    attribute :recorded_by_id, :uuid, public?: true, writable?: false
    create_timestamp :inserted_at
  end
end
