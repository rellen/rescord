defmodule Rescord.Comments.Follow do
  @moduledoc """
  A person follows a record, and gets a notification for each new comment
  on it (issue 29). A person follows a record after they write on it or
  are told on it (`Rescord.Comments.Changes.FollowAfterWrite`), and with
  the button of the comments.

  A follow is a small fact of one person: not temporal, no archive and no
  paper trail. A person reads and ends only their own.
  """

  use Rescord.Resource,
    domain: Rescord.Comments,
    temporal?: false,
    archive?: false,
    paper_trail?: false,
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  postgres do
    table "comment_follows"

    check_constraints do
      check_constraint :resident_id, "one_record",
        check:
          "num_nonnulls(resident_id, task_id, expense_id, transfer_id, journal_entry_id) = 1",
        message:
          "must name a resident, a task, an expense, a transfer or a journal entry, and one only"
    end

    custom_indexes do
      index [:resident_id], where: "resident_id IS NOT NULL"
      index [:task_id], where: "task_id IS NOT NULL"
      index [:expense_id], where: "expense_id IS NOT NULL"
      index [:transfer_id], where: "transfer_id IS NOT NULL"
      index [:journal_entry_id], where: "journal_entry_id IS NOT NULL"
    end
  end

  actions do
    defaults [:read]

    create :follow do
      description "The actor follows a record"
      accept [:resident_id, :task_id, :expense_id, :transfer_id, :journal_entry_id]
      upsert? true
      upsert_identity :one_follow
      upsert_fields [:user_id]
      change Rescord.Comments.Changes.SetUser
      validate Rescord.Comments.Validations.OneRecord
      validate Rescord.Comments.Validations.SubjectReadable, before_action?: true
    end

    create :add do
      description "A person follows a record after they wrote or were told. Only `write` runs it"
      accept [:user_id, :resident_id, :task_id, :expense_id, :transfer_id, :journal_entry_id]
      upsert? true
      upsert_identity :one_follow
      upsert_fields [:user_id]
    end

    destroy :unfollow do
      description "The actor stops following a record"
    end
  end

  policies do
    # A follow is of one person: no bypass for a root user.
    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :resident_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
    attribute :expense_id, :uuid, public?: true
    attribute :transfer_id, :uuid, public?: true
    attribute :journal_entry_id, :uuid, public?: true

    create_timestamp :inserted_at, public?: true
  end

  identities do
    identity :one_follow,
             [:user_id, :resident_id, :task_id, :expense_id, :transfer_id, :journal_entry_id],
             nils_distinct?: false
  end
end
