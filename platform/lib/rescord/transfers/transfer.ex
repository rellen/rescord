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

      sending --deliver--> sent --accept---> accepted
         |                   |---decline--> declined
         |                   |---withdraw-> withdrawn
         |---fail-----> failed --send_again--> sending
         |---withdraw-> withdrawn     |---withdraw---> withdrawn

  A transfer to a partner on this server copies its files in a job, after
  the commit of the send (ADR 0100). `send` writes the copy with the state
  `sending`, and the sources of its files in `sources`, and emits
  `:transfer_started`. The job runs `copy_files`, which copies each file
  that is not copied yet, writes the count (`progress`), and runs
  `deliver` after the last one: then the transfer is `sent`, and the
  refuge that receives it sees it. A transfer with no file is `sent` at
  once. A file that is not in the store, or a store that refuses each of
  the 10 tries of the job, makes it `failed`; the refuge that sends it
  sends it again or withdraws it. Only the refuge that sends a transfer
  sees it while it is `sending` or `failed`.

  No person runs `copy_files`, `progress`, `deliver` or `fail`: their
  policy is the signal alone (ADR 0067).

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
    # The copy is large, and it never changes. The sources and the count
    # are the work of the job, and not a fact of the transfer.
    ignore_attributes [:snapshot, :sources, :files_copied]
    # Each write of the count is a step of the job. The state that it
    # ends in, `sent` or `failed`, is a version.
    ignore_actions [:progress]
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
      change Changes.StartCopy
      emit Rescord.Transfers.Signals, :transfer_started, dynamic?: true
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
      description "Takes back a transfer that has no answer, while its files are on their way too"
      accept []
      require_atomic? false
      change filter(expr(state in [:sending, :sent, :failed]))
      change set_attribute(:state, :withdrawn)
      change Changes.Answer
    end

    update :send_again do
      description "Copies the files of a transfer that failed again, from where the copy stopped"
      accept []
      require_atomic? false
      change filter(expr(state == :failed))
      change set_attribute(:state, :sending)
      change set_attribute(:failure, nil)
      change Changes.StartCopy
      emit Rescord.Transfers.Signals, :transfer_started, dynamic?: true
    end

    action :copy_files do
      description "Copies the files of a transfer that is sending. A job runs this for `:transfer_started`, and no role has a grant for it"

      # Not the struct as the type, as `Rescord.Accounts.Member` says.
      argument :signal, :struct,
        allow_nil?: false,
        constraints: [instance_of: Rescord.Transfers.Signals.TransferStarted]

      run Rescord.Transfers.Actions.CopyFiles
    end

    # It writes the count in each state that has sources, so the file check
    # names each file that a job put, after a withdraw too. The count never
    # goes back: two jobs of the same transfer can write it (ADR 0100).
    update :progress do
      description "Writes how many files of a transfer whose files a job copies are in the store"
      accept []
      require_atomic? false
      argument :files_copied, :integer, allow_nil?: false, constraints: [min: 0]
      change filter(expr(not is_nil(sources)))

      change atomic_update(
               :files_copied,
               expr(
                 if files_copied > ^arg(:files_copied),
                   do: files_copied,
                   else: ^arg(:files_copied)
               )
             )
    end

    update :deliver do
      description "Makes a transfer whose files are each copied sent: the refuge that receives it sees it now"
      accept []
      require_atomic? false
      change filter(expr(state == :sending))
      change set_attribute(:state, :sent)
      change atomic_update(:files_copied, expr(files_total))
      change set_attribute(:sources, nil)
    end

    update :fail do
      description "Stops a transfer whose files did not arrive, with the reason"
      accept []
      require_atomic? false

      argument :failure, :atom,
        allow_nil?: false,
        constraints: [one_of: [:file_missing, :store_refused, :interrupted]]

      change filter(expr(state == :sending))
      change set_attribute(:state, :failed)
      change set_attribute(:failure, arg(:failure))
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if Checks.MemberOf
    end

    policy action([:send, :export, :withdraw, :send_again]) do
      authorize_if {Checks.PowerIn, side: :from}
    end

    # The job of a transfer has no person: the send was the decision
    # (ADR 0067, ADR 0100).
    policy action([:copy_files, :progress, :deliver, :fail]) do
      authorize_if signal_in(Rescord.Transfers.Signals, :transfer_started)
    end

    policy action([:accept, :decline, :import]) do
      authorize_if {Checks.PowerIn, side: :to}
    end
  end

  # A page of each of the two refuges hears of it (ADR 0096).
  pub_sub do
    publish_all :create, [[:from_organisation_id, :to_organisation_id], "transfers"]
    publish_all :update, [[:from_organisation_id, :to_organisation_id], "transfers"]
    publish_all :destroy, [[:from_organisation_id, :to_organisation_id], "transfers"]
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
      constraints one_of: [:sending, :failed, :sent, :accepted, :declined, :withdrawn, :exported]
    end

    # For each file of the copy, its id in the copy and its key in the
    # store of the refuge that sends it, while the job copies them. The
    # copy itself holds no key (ADR 0057).
    attribute :sources, {:array, :map} do
      public? false
      writable? false
      description "The files that the job copies, in order, until the transfer is sent"
    end

    attribute :files_total, :integer do
      allow_nil? false
      default 0
      public? true
      writable? false
      description "The files that the copy names and the job copies"
    end

    attribute :files_copied, :integer do
      allow_nil? false
      default 0
      public? true
      writable? false

      description "The first files of the sources that are in the store of the refuge that receives it"
    end

    attribute :failure, :atom do
      public? true
      writable? false
      constraints one_of: [:file_missing, :store_refused, :interrupted]
      description "Why a transfer that failed did not arrive"
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

  # The files of a transfer go in a job: Oban writes the job in the
  # transaction of the send, runs it after the commit, and runs it again
  # after a fault. Oban waits longer before each try, so 10 tries take
  # about 20 minutes. A person waits for this, and sends a transfer that
  # failed again with one click (ADR 0100).
  signals_in do
    from Rescord.Transfers.Signals do
      on :transfer_started, :copy_files,
        delivery: {AshOban.Signals, queue: :transfers, max_attempts: 10, shared_context: [:job]}
    end
  end

  identities do
    # A file imports one time: the second import of it is refused.
    identity :one_import, [:to_organisation_id, :export_id],
      message: "is a transfer file that this refuge imported already"
  end
end
