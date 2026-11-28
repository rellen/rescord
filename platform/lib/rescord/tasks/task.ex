defmodule Rescord.Tasks.Task do
  @moduledoc """
  One piece of work that a member does for a resident, a group or a location
  (`docs/domain.md`, section 5.7, and ADR 0032).

  A task is due at a time. It names members, or it is for each member: any
  member can take a task. When one of the members completes the task, it is
  done for all of them (the maintainer, 18 November 2026). A member completes a task, or skips
  it with a reason, and can open it again.

  ## States

      due --complete--> done
      due --skip------> skipped
      due --skip_left_alone--> skipped   (the removal of its only resident)
      done, skipped --reopen--> due

  AshStateMachine holds the states, so this resource is not temporal
  (ADR 0012). Its history is in its paper trail.

  ## A dose

  A task can name a prescription. When a member completes such a task,
  Rescord writes a journal entry for the dose, for the resident of the
  prescription. It does not change the inventory.

  ## Two members at the same time

  The state machine reads the state of the record that the caller has in
  hand, which can be old. Each action that changes the state also has a
  filter on the state in the database. When a second member completes a
  task that a first member completed a moment before, the second action
  returns `Ash.Error.Changes.StaleRecord`, and writes no second dose.

  `Rescord.Tasks.TaskSubject` names what a task is for.

  ## A task that loses its only subject

  When an administrator removes a resident, a task that is due and named
  only that resident is skipped, with the reason "The resident was
  removed" (ADR 0067). A member can open it again. It does not make the
  next tasks of a routine: the routine has lost the resident too, and the
  job of each hour makes its tasks.
  """

  use Rescord.Resource,
    domain: Rescord.Tasks,
    temporal?: false,
    extensions: [AshStateMachine],
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Tasks

  postgres do
    table "tasks"

    # A page reads the tasks of a day, and a routine reads its own.
    custom_indexes do
      index [:due_at]
      index [:routine_id]
    end
  end

  state_machine do
    initial_states [:due]
    default_initial_state :due

    transitions do
      transition :complete, from: :due, to: :done
      transition :skip, from: :due, to: :skipped
      transition :skip_left_alone, from: :due, to: :skipped
      transition :reopen, from: [:done, :skipped], to: :due
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :plan do
      description "Plans a task, for a time that can be months ahead"
      accept [:title, :note, :due_at, :kind_id, :assignee_ids, :prescription_id]
      argument :resident_ids, {:array, :uuid}, default: []
      argument :group_ids, {:array, :uuid}, default: []
      argument :location_ids, {:array, :uuid}, default: []
      change Tasks.Changes.WriteSubjects
    end

    create :generate do
      description "Makes a task of a routine. `SyncTasks` runs this, and no role has a grant for it"

      accept [
        :title,
        :note,
        :due_at,
        :kind_id,
        :assignee_ids,
        :prescription_id,
        :routine_id
      ]

      argument :resident_ids, {:array, :uuid}, default: []
      argument :group_ids, {:array, :uuid}, default: []
      argument :location_ids, {:array, :uuid}, default: []
      change Tasks.Changes.WriteSubjects
    end

    update :revise do
      accept [:title, :note, :due_at, :kind_id]
    end

    update :take do
      description "The actor is one of the members that the task is for"
      accept []
      require_atomic? false
      change Tasks.Changes.TakeTask
    end

    update :give do
      description "Gives the task to members, or to each member when `assignee_ids` is empty"
      accept [:assignee_ids]
    end

    update :complete do
      description "Completes the task. A task with a prescription writes a journal entry for the dose"
      accept [:note]
      require_atomic? false
      change filter(expr(state == :due))
      change transition_state(:done)
      change Tasks.Changes.Finish
      change Tasks.Changes.WriteDose
      change Tasks.Changes.NextOfRoutine
    end

    update :skip do
      description "Skips the task, with the reason"
      accept [:skip_reason]
      require_atomic? false
      validate present(:skip_reason), message: "is required to skip a task"
      change filter(expr(state == :due))
      change transition_state(:skipped)
      change Tasks.Changes.Finish
      change Tasks.Changes.NextOfRoutine
    end

    update :skip_left_alone do
      description "Skips a task that lost its only subject, with a reason that says so. The removal of a resident runs this, and no role has a grant for it"

      accept []
      require_atomic? false
      change filter(expr(state == :due))
      change transition_state(:skipped)
      change set_attribute(:skip_reason, "The resident was removed")
      change Tasks.Changes.Finish
    end

    update :reopen do
      accept []
      require_atomic? false
      change filter(expr(state in [:done, :skipped]))
      change transition_state(:due)
      change set_attribute(:finished_at, nil)
      change set_attribute(:finished_by_id, nil)
      change set_attribute(:skip_reason, nil)
    end

    destroy :cancel do
      description "Cancels a task that is not necessary. The row and its history stay"
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

    attribute :due_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    # The ids below name records of temporal resources, and of the users. The
    # database can hold no key from a table with no period to one with a
    # period, so each is a plain id.
    attribute :kind_id, :uuid, public?: true
    attribute :prescription_id, :uuid, public?: true

    attribute :assignee_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true

      description "The users that the task is for. A task with none is for each member. One of them completes it"
    end

    attribute :skip_reason, :string do
      public? true
      constraints max_length: 200
    end

    attribute :finished_at, :utc_datetime_usec do
      public? true
      writable? false
    end

    attribute :finished_by_id, :uuid do
      public? true
      writable? false
    end
  end

  relationships do
    has_many :subjects, Tasks.TaskSubject do
      public? true
    end

    belongs_to :routine, Tasks.Routine do
      public? true
      description "The routine that made the task, or none"
    end

    belongs_to :kind, Rescord.Lists.TaskKind do
      public? true
      define_attribute? false
      source_attribute :kind_id
      temporal_keys {nil, :valid_at}
    end
  end
end
