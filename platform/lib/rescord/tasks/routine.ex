defmodule Rescord.Tasks.Routine do
  @moduledoc """
  A task that repeats (`docs/domain.md`, section 5.7, and ADR 0033): what to
  do, for which residents, groups and locations, and when.

  ## When

  A routine has a pattern (`Rescord.Tasks.RoutinePattern`), a first day, a
  last day or none, and one time of the day or more. The days and the times
  are those of the organisation, in its time zone.

  ## Its tasks

  Rescord makes a `Rescord.Tasks.Task` for each time of the routine, a
  number of days ahead: `days_ahead` of the routine, or else the setting of
  the organisation. `generated_until` is the instant up to which the tasks
  exist. `Rescord.Tasks.Changes.SyncTasks` makes them: when the routine
  starts, when a member changes it, and each hour in a job.

  A change to a routine cancels its tasks that are due after now, and makes
  them again from the new facts. A pause cancels them, and so does the end
  of the routine. The tasks that are done, skipped or late stay.

  ## Not temporal

  The mark `generated_until` moves each day, and a task names its routine
  with a key of the database. So this resource is not temporal, like the
  task. Its history is in its paper trail, which does not record the moves
  of the mark.

  The routine names its subjects, its kind, its member and its prescription
  by plain ids, as a task does.
  """

  use Rescord.Resource,
    domain: Rescord.Tasks,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Tasks.Changes.{ShapePattern, SyncTasks}

  @facts [
    :title,
    :note,
    :kind_id,
    :assignee_id,
    :pattern,
    :every,
    :weekdays,
    :times,
    :starts_on,
    :ends_on,
    :days_ahead,
    :resident_ids,
    :group_ids,
    :location_ids
  ]

  postgres do
    table "routines"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    # These two move the mark only, each hour.
    ignore_actions [:generate, :mark]
  end

  actions do
    defaults [:read]

    create :start do
      description "Starts a routine, and makes its first tasks"
      accept @facts ++ [:prescription_id]
      change ShapePattern
      change {SyncTasks, make?: true}
    end

    update :revise do
      description "Changes a routine. Its tasks that are due after now are made again"
      accept @facts
      require_atomic? false
      change ShapePattern
      change {SyncTasks, drop?: true, make?: true}
    end

    update :pause do
      description "Stops the routine for a time. Its tasks that are due after now are cancelled"
      accept []
      require_atomic? false
      change set_attribute(:paused, true)
      change {SyncTasks, drop?: true}
    end

    update :resume do
      description "Starts a routine again after a pause, from now"
      accept []
      require_atomic? false
      change set_attribute(:paused, false)
      change {SyncTasks, make?: true}
    end

    update :generate do
      description "Makes the tasks up to the horizon. The job runs this, and no role has a grant for it"
      accept []
      require_atomic? false
      argument :now, :utc_datetime_usec
      change {SyncTasks, make?: true}
    end

    update :mark do
      description "Moves the instant up to which the tasks exist. `SyncTasks` runs this"
      accept []
      argument :until, :utc_datetime_usec, allow_nil?: false
      change set_attribute(:generated_until, arg(:until))
    end

    destroy :remove do
      description "Ends the routine. Its tasks that are due after now are cancelled"
      require_atomic? false
      change {SyncTasks, drop?: true}
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 120
    end

    attribute :note, :string do
      public? true
      constraints max_length: 1000
    end

    attribute :kind_id, :uuid, public?: true
    attribute :prescription_id, :uuid, public?: true

    attribute :assignee_id, :uuid do
      public? true
      description "The user that each task is for. With none, each task is for each member"
    end

    attribute :pattern, Rescord.Tasks.RoutinePattern do
      allow_nil? false
      public? true
    end

    attribute :every, :integer do
      public? true
      description "The number of days of `:interval`, or of months of `:monthly`"
    end

    attribute :weekdays, {:array, :integer} do
      allow_nil? false
      default []
      public? true
      description "The days of the week of `:weekly`: 1 is Monday, and 7 is Sunday"
    end

    attribute :times, {:array, :time} do
      allow_nil? false
      default []
      public? true
      description "The times of the day, in the time zone of the organisation"
    end

    attribute :starts_on, :date do
      allow_nil? false
      public? true
    end

    attribute :ends_on, :date, public?: true

    attribute :days_ahead, :integer do
      public? true
      constraints min: 1, max: 400

      description "How many days ahead the tasks exist. With none, the setting of the organisation"
    end

    attribute :resident_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true
    attribute :group_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true
    attribute :location_ids, {:array, :uuid}, allow_nil?: false, default: [], public?: true

    attribute :paused, :boolean do
      allow_nil? false
      default false
      public? true
      writable? false
    end

    attribute :generated_until, :utc_datetime_usec do
      public? true
      writable? false
      description "The instant up to which the tasks of the routine exist"
    end
  end

  relationships do
    has_many :tasks, Rescord.Tasks.Task do
      public? true
    end

    belongs_to :kind, Rescord.Lists.TaskKind do
      public? true
      define_attribute? false
      source_attribute :kind_id
      temporal_keys {nil, :valid_at}
    end
  end
end
