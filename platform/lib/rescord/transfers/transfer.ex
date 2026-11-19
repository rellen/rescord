defmodule Rescord.Transfers.Transfer do
  @moduledoc """
  A resident that one refuge sends to a partner refuge, as a copy that
  cannot change (ADR 0042).

  The copy is a snapshot of the record at the time of the transfer
  (`Rescord.Transfers.Snapshot`): the facts and the medical history of the
  resident always, and the parts that the sender chooses. The refuge that
  sends gives its default parts as a setting, and the sender can change
  them for each transfer.

  Nothing appears at the refuge that receives until a person there with
  the power `:transfers` accepts the transfer, and that person can decline
  it. After the acceptance, each member there reads the copy. The sender
  can withdraw a transfer that has no answer.

  A transfer to a partner on another server is a file (ADR 0043). The
  refuge that sends it keeps a record with the state `exported`, and the
  refuge that imports the file gets a transfer that waits for its answer,
  as above.

  ## States

      sent --accept---> accepted
      sent --decline--> declined
      sent --withdraw-> withdrawn

  The record is outside the schemas of the two refuges. The transfer does
  not change the record of the resident at the refuge that sends it: that
  refuge records the departure itself.
  """

  use Rescord.Resource,
    domain: Rescord.Transfers,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Transfers.{Changes, Checks}

  postgres do
    table "transfers"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # The copy is large, and it never changes.
    ignore_attributes [:snapshot]
  end

  actions do
    defaults [:read]

    create :send do
      description "Sends a copy of a resident to a partner refuge"
      accept [:note]
      argument :organisation_id, :uuid, allow_nil?: false
      argument :partner_id, :uuid, allow_nil?: false
      argument :resident_id, :uuid, allow_nil?: false
      argument :parts, {:array, :atom}, default: []
      change Changes.SendTransfer
    end

    create :export do
      description "Writes a transfer file of a resident for a partner on another server"
      accept [:note]
      argument :organisation_id, :uuid, allow_nil?: false
      argument :remote_partner_id, :uuid, allow_nil?: false
      argument :resident_id, :uuid, allow_nil?: false
      argument :parts, {:array, :atom}, default: []
      change Changes.ExportTransfer
    end

    create :import do
      description "Reads a transfer file from a partner on another server. It waits for an answer"
      accept []
      argument :organisation_id, :uuid, allow_nil?: false
      argument :file, :binary, allow_nil?: false, sensitive?: true
      change Changes.ImportTransfer
    end

    update :accept do
      accept []
      require_atomic? false
      change filter(expr(state == :sent))
      change set_attribute(:state, :accepted)
      change Changes.Answer
    end

    update :decline do
      accept []
      require_atomic? false
      change filter(expr(state == :sent))
      change set_attribute(:state, :declined)
      change Changes.Answer
    end

    update :withdraw do
      accept []
      require_atomic? false
      change filter(expr(state == :sent))
      change set_attribute(:state, :withdrawn)
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

    policy action([:send, :export, :withdraw]) do
      authorize_if {Checks.PowerIn, side: :from}
    end

    policy action([:accept, :decline, :import]) do
      authorize_if {Checks.PowerIn, side: :to}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :from_organisation_id, :uuid do
      public? true
      writable? false
      description "The refuge that sent it, on this server, or none for an import"
    end

    attribute :to_organisation_id, :uuid do
      public? true
      writable? false
      description "The refuge that receives it, on this server, or none for an export"
    end

    attribute :remote_partner_id, :uuid do
      public? true
      writable? false
      description "The partner on another server, for an export or an import (ADR 0043)"
    end

    attribute :export_id, :uuid do
      public? true
      writable? false
      description "The id of the transfer at the refuge that exported it, for an import"
    end

    attribute :resident_id, :uuid do
      public? true
      writable? false
      description "The resident in the schema of the refuge that sent it, on this server"
    end

    attribute :resident_name, :string do
      public? true
      writable? false
      description "The name of the resident at the transfer, for a list"
    end

    attribute :parts, {:array, :atom} do
      allow_nil? false
      default []
      public? true
      writable? false
      description "The parts of the copy other than the facts and the medical history"
    end

    attribute :snapshot, :map do
      allow_nil? false
      public? true
      writable? false
      description "The copy of the resident at the transfer"
    end

    attribute :note, :string do
      public? true
      constraints max_length: 2000
    end

    attribute :state, :atom do
      allow_nil? false
      default :sent
      public? true
      writable? false
      constraints one_of: [:sent, :accepted, :declined, :withdrawn, :exported]
    end

    attribute :sent_by_id, :uuid, public?: true, writable?: false
    attribute :answered_by_id, :uuid, public?: true, writable?: false
    attribute :answered_at, :utc_datetime_usec, public?: true, writable?: false

    create_timestamp :sent_at
  end

  relationships do
    belongs_to :remote_partner, Rescord.Transfers.RemotePartner do
      public? true
      define_attribute? false
      source_attribute :remote_partner_id
    end

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

  identities do
    # A file imports one time: the second import of it is refused.
    identity :one_import, [:to_organisation_id, :export_id],
      message: "is a transfer file that this refuge imported already"
  end
end
