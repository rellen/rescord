defmodule Rescord.Notifications.Notification do
  @moduledoc """
  Something new for one person of the organisation (issue 29, ADR 0106):
  a comment that told them (`:told`), or a comment on a record that they
  follow (`:comment`).

  The listener of `:commented` makes the notifications, in the transaction
  of the comment (`Rescord.Notifications.Actions.NotifyOfComment`). Each one
  then starts a job (the trigger `deliver`), which sends it on each channel
  that the person chose and that the server has: a device of Web Push,
  a topic of ntfy (`Rescord.Notifications.Channel`). A channel carries a
  pointer, never the words of the comment.

  A notification is of one person: they read it and mark it as read, and
  nobody else, a root user neither. It goes with its comment (a foreign
  key), and the job of each night deletes it 30 days after it was read and
  90 days after it was made (`Rescord.Notifications.prune/2`). Not
  temporal, no archive, no paper trail: it is not a record of the rescue.
  """

  use Rescord.Resource,
    domain: Rescord.Notifications,
    temporal?: false,
    archive?: false,
    paper_trail?: false,
    extensions: [AshOban],
    authorizers: [Ash.Policy.Authorizer]

  @type t :: %__MODULE__{}

  @kinds [:told, :comment]

  postgres do
    table "notifications"

    references do
      reference :comment, on_delete: :delete
    end

    custom_indexes do
      index [:user_id, :id]
      index [:comment_id]
    end
  end

  oban do
    triggers do
      trigger :deliver do
        action :deliver
        queue :default
        where expr(is_nil(delivered_at))
        # No scheduler: `make` starts the job of its notification.
        scheduler_cron false
        # A channel that failed tries again; one that took it is not sent
        # again (`delivered`).
        max_attempts 5
        log_errors? false
        log_final_error? false
        worker_module_name Rescord.Notifications.Notification.Workers.Deliver
        scheduler_module_name Rescord.Notifications.Notification.Schedulers.Deliver
      end
    end
  end

  actions do
    defaults [:read]

    read :mine do
      description "The newest notifications of the actor"
      filter expr(user_id == ^actor(:id))
      prepare build(sort: [id: :desc], limit: 50)
    end

    create :make do
      description "A notification for one person. Only the listener of `:commented` runs it"
      accept [:user_id, :kind, :comment_id]
      change run_oban_trigger(:deliver)
    end

    update :deliver do
      description "Sends the notification on the channels of its person. Only the job runs it"
      accept []
      require_atomic? false
      # A request to a push service is no work for a transaction.
      transaction? false
      change Rescord.Notifications.Changes.Deliver
    end

    update :mark_read do
      description "The person read the notification"
      accept []
      change set_attribute(:read_at, &DateTime.utc_now/0)
    end

    destroy :forget do
      description "Deletes a notification that is old. Only the job of each night runs it"
    end

    action :notify_of_comment do
      description "Makes the notifications of a new comment. The listener of `:commented` runs it"

      # Not the struct as the type: AshBoundary exports a type that a public
      # resource names, and `boundary` does not know a struct that a signal
      # module generates (ADR 0067).
      argument :signal, :struct,
        allow_nil?: false,
        constraints: [instance_of: Rescord.Comments.Signals.Commented]

      run Rescord.Notifications.Actions.NotifyOfComment
    end
  end

  policies do
    # AshOban asks the policy for the read and the action of a trigger.
    bypass AshOban.Checks.AshObanInteraction do
      authorize_if always()
    end

    # No bypass for a root user: a notification is of one person.
    policy always() do
      # The comment was the decision: the listener makes the notifications.
      authorize_if signal_in(Rescord.Comments.Signals, :commented)
      # The erasure of the person on request is the decision (ADR 0105).
      authorize_if signal_in(Rescord.Accounts.Signals, :member_erased)
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    # The id holds the time, so the newest sort first.
    uuid_v7_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
      description "The person whom the notification is for"
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :read_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    attribute :delivered, {:array, :atom} do
      allow_nil? false
      default []
      public? true
      writable? false
      description "The channels that took the notification"
    end

    attribute :tries, :integer do
      allow_nil? false
      default 0
      public? true
      writable? false
      description "How many times the job sent it"
    end

    attribute :delivered_at, :utc_datetime_usec do
      public? true
      writable? false
      description "When the job ended, whatever each channel did"
    end

    create_timestamp :inserted_at, public?: true
  end

  relationships do
    belongs_to :comment, Rescord.Comments.Comment do
      allow_nil? false
      public? true
    end
  end

  # A new comment makes its notifications in a job, after the transaction
  # of the comment: the writer does not wait, and a fault makes no comment
  # fail. Oban tries again after a fault.
  signals_in do
    # The notifications of a person erased on request go (ADR 0105).
    from Rescord.Accounts.Signals do
      on :member_erased, :forget_of_erased_member,
        action: :forget,
        get_by: [user_id: :user_id]
    end

    from Rescord.Comments.Signals do
      on :commented, :notify_of_comment,
        delivery: {AshOban.Signals, queue: :default, max_attempts: 5}
    end
  end

  @doc "The kinds of notification."
  @spec kinds() :: [atom]
  def kinds, do: @kinds
end
