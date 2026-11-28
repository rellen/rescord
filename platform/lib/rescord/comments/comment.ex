defmodule Rescord.Comments.Comment do
  @moduledoc """
  A comment of a member on one record of the organisation: a resident, a
  task, a transfer, an expense or a journal entry (issue 29, ADR 0106).

  The words are a small part of Markdown, which `RescordWeb.Markdown`
  renders with no raw HTML. The writer
  can tell members (`told_ids`), who get a notification and follow the
  record from then on, as the writer does.

  ## Who reads and writes

  The policy is the grants (`Rescord.Comments.Grants`). Each role reads the
  comments of the records that each role reads, and the comments of an
  expense only where the person reads the expense. `write` reads the record
  as the actor first (`Rescord.Comments.Validations.SubjectReadable`), and
  each person told must be a member (`Rescord.Comments.Validations.Members`).
  The writer changes and deletes their own comment; a person with the power
  `moderate_comments` deletes any.

  ## Deleted for real

  The resource is not temporal and has no archive: a delete removes the
  row, and with it its notifications (a foreign key). The paper trail keeps
  who wrote, changed and deleted, and when, with "REDACTED" in place of the
  words, so no version holds the text of a comment.
  """

  use Rescord.Resource,
    domain: Rescord.Comments,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshRateLimiter]

  alias Rescord.Comments.{Changes, Validations}

  @type t :: %__MODULE__{}

  postgres do
    table "comments"

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
      index [:author_id]
    end

    references do
      reference :task, on_delete: :delete
      reference :expense, on_delete: :delete
    end
  end

  # A comment can tell members, who get a notification on each device. One
  # person writes 10 comments in a minute at most (ADR 0115), so nobody can
  # send notifications without end. The count is of this node, and a restart
  # forgets it (ADR 0020).
  rate_limit do
    backend Rescord.RateLimit
    action :write, limit: 10, per: :timer.minutes(1), key: &__MODULE__.writer_key/2
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # A version says who and when, and never what: the text of a deleted
    # comment must be gone (issue 29).
    sensitive_attributes :redact
    # A comment is deleted for real, and its versions stay: they name it by
    # its id alone, with no foreign key.
    reference_source? false
  end

  actions do
    defaults [:read]

    create :write do
      description "Writes a comment on one record, and tells the members of `told_ids`"

      accept [
        :body,
        :told_ids,
        :resident_id,
        :task_id,
        :expense_id,
        :transfer_id,
        :journal_entry_id
      ]

      change Rescord.Accounts.Changes.SetAuthor
      validate Validations.OneRecord
      # These read as the actor, so the policy answers first.
      validate Validations.SubjectReadable, before_action?: true
      validate Validations.Members, before_action?: true
      change Changes.FollowAfterWrite

      emit Rescord.Comments.Signals, :commented, fields: [comment_id: :id]
    end

    update :revise do
      description "Changes the words of a comment. It tells nobody again"
      accept []
      # Sensitive, so the version of the change keeps no word of it.
      argument :body, :string,
        allow_nil?: false,
        sensitive?: true,
        constraints: [max_length: 4_000, trim?: true]

      require_atomic? false
      change set_attribute(:body, arg(:body))
      change set_attribute(:edited_at, &DateTime.utc_now/0)
    end

    destroy :delete do
      description "Deletes a comment for real, with its notifications"
    end

    destroy :erase do
      description "Deletes each comment of one person, for a person who asks for that. A moderator runs it"
    end

    read :of_erased_author do
      description "The comments of a person erased on request, when the erasure did not keep them (ADR 0105)"
      argument :author_id, :uuid, allow_nil?: false
      argument :keep_comments, :boolean, allow_nil?: false
      filter expr(author_id == ^arg(:author_id) and ^arg(:keep_comments) == false)
      pagination keyset?: true, required?: false
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      # The erasure of the person on request is the decision (ADR 0105).
      authorize_if signal_in(Rescord.Accounts.Signals, :member_erased)
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    # The id holds the time, so the comments of a record sort by it.
    uuid_v7_primary_key :id

    attribute :body, :string do
      allow_nil? false
      public? true
      sensitive? true
      constraints min_length: 1, max_length: 4_000, trim?: true
      description "The words of the comment, in a small part of Markdown"
    end

    attribute :resident_id, :uuid, public?: true
    attribute :task_id, :uuid, public?: true
    attribute :expense_id, :uuid, public?: true
    attribute :transfer_id, :uuid, public?: true
    attribute :journal_entry_id, :uuid, public?: true

    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
      description "The user who wrote the comment"
    end

    attribute :told_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
      description "The users whom the writer told"
    end

    attribute :edited_at, :utc_datetime_usec do
      public? true
      writable? false
      description "When the writer last changed the words"
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    # The records that the pages name. A comment is not temporal, so it
    # holds the plain id of a temporal resident (ADR 0032).
    belongs_to :resident, Rescord.Residents.Resident do
      public? true
      define_attribute? false
      source_attribute :resident_id
      temporal_keys {nil, :valid_at}
    end

    belongs_to :task, Rescord.Tasks.Task do
      public? true
      define_attribute? false
      source_attribute :task_id
    end

    belongs_to :expense, Rescord.Expenses.Expense do
      public? true
      define_attribute? false
      source_attribute :expense_id
    end

    # A journal entry is temporal too: a plain id, as for a resident.
    belongs_to :journal_entry, Rescord.Journal.JournalEntry do
      public? true
      define_attribute? false
      source_attribute :journal_entry_id
      temporal_keys {nil, :valid_at}
    end
  end

  # The comments of a person erased on request go, unless the person who
  # erased chose to keep them, signed Former member N (ADR 0105, issue 31,
  # calls 7 and 8).
  signals_in do
    from Rescord.Accounts.Signals do
      on :member_erased, :erase_of_erased_member,
        action: :erase,
        read_action: :of_erased_author,
        args: [:keep_comments, author_id: :user_id]
    end
  end

  @doc false
  def writer_key(_changeset, %{actor: %{id: id}}) when is_binary(id), do: "comments/person/" <> id
  def writer_key(_changeset, _context), do: "comments/nobody"
end
