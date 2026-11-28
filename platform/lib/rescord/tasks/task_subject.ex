defmodule Rescord.Tasks.TaskSubject do
  @moduledoc """
  What a task is for: a resident, a group or a location, and never more than
  one of them in one record (`docs/domain.md`, section 5.7). A task has zero
  subjects or more.

  `Rescord.Tasks.Task` writes the subjects of a new task: no role has a
  grant to write one in another way.

  A subject goes when its resident is removed (ADR 0067): the row is
  archived. The task stays for its other subjects. A task that is due and
  has no subject left is skipped, with a reason
  (`Rescord.Tasks.Changes.SkipTaskLeftAlone`).

  When a resident leaves, the same happens for the tasks that are due. A
  task that is done or skipped keeps the resident: it is its history.
  """

  use Rescord.Resource,
    domain: Rescord.Tasks,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "task_subjects"

    check_constraints do
      check_constraint :resident_id, "one_subject",
        check: "num_nonnulls(resident_id, group_id, location_id) = 1",
        message: "must name a resident, a group or a location, and one only"
    end

    references do
      reference :task, on_delete: :delete
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    read :of_resident do
      description "The subjects that name a resident"
      argument :resident_id, :uuid, allow_nil?: false
      filter expr(resident_id == ^arg(:resident_id))
      # The listener reads the subjects in pages: its change is not atomic.
      pagination keyset?: true, required?: false
    end

    read :of_resident_in_due_tasks do
      description "The subjects that name a resident, in the tasks that are due"
      argument :resident_id, :uuid, allow_nil?: false
      filter expr(resident_id == ^arg(:resident_id) and task.state == :due)
      pagination keyset?: true, required?: false
    end

    create :add do
      accept [:task_id, :resident_id, :group_id, :location_id]
    end

    destroy :drop do
      description "Takes a subject that is not there any more out of its task. A listener runs this, and no role has a grant for it"

      # A task that is due, and has no subject left, is skipped.
      require_atomic? false
      change {Rescord.Tasks.Changes.SkipTaskLeftAlone, reason: "The resident was removed"}
    end

    destroy :drop_departed do
      description "Takes a resident that left out of a task that is due. A listener runs this, and no role has a grant for it"

      require_atomic? false
      change {Rescord.Tasks.Changes.SkipTaskLeftAlone, reason: "The resident left"}
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      # The removal of a resident is the decision (ADR 0067).
      authorize_if signal_in(Rescord.Residents.Signals, :resident_removed)
      authorize_if signal_in(Rescord.Residents.Signals, :resident_departed)
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :resident_id, :uuid, public?: true
    attribute :group_id, :uuid, public?: true
    attribute :location_id, :uuid, public?: true
  end

  relationships do
    belongs_to :task, Rescord.Tasks.Task do
      allow_nil? false
      public? true
    end

    belongs_to :resident, Rescord.Residents.Resident do
      public? true
      define_attribute? false
      source_attribute :resident_id
      temporal_keys {nil, :valid_at}
    end

    belongs_to :group, Rescord.Residents.Group do
      public? true
      define_attribute? false
      source_attribute :group_id
      temporal_keys {nil, :valid_at}
    end

    belongs_to :location, Rescord.Locations.Location do
      public? true
      define_attribute? false
      source_attribute :location_id
      temporal_keys {nil, :valid_at}
    end
  end

  signals_in do
    from Rescord.Residents.Signals do
      on :resident_removed, :drop_of_removed_resident,
        action: :drop,
        read_action: :of_resident,
        args: [:resident_id]

      # A resident that left stays in the tasks that are done or skipped:
      # they are its history. It goes out of the tasks that are due.
      on :resident_departed, :drop_of_departed_resident,
        action: :drop_departed,
        read_action: :of_resident_in_due_tasks,
        args: [:resident_id]
    end
  end
end
