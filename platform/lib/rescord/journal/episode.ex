defmodule Rescord.Journal.Episode do
  @moduledoc """
  One time that a resident has a condition, from its first day to its last
  day (ADR 0083): the bumblefoot of Biscuit since 3 November. The pages call
  it a condition of the resident.

  An episode names a value of the list `condition` of the organisation. It
  is ongoing while it has no last day, and resolved after. `chronic` marks a
  condition that the resident keeps. A condition that comes again is a new
  episode, so the episodes of a condition say how often it comes.

  ## How an episode starts

  A journal entry of the kind `diagnosis` starts an episode, or joins the
  ongoing one of the same condition: `Rescord.Journal.Changes.LinkEpisode`
  runs `start` as a part of the write of the entry. No role has a grant for
  `start` or for `rename`, so the policy of the entry decides. Each other
  entry can name an episode of its resident in `episode_id`.

  A member marks an episode as resolved, opens it again, and revises its
  days, its mark and its note. `remove` archives an episode that was a
  mistake. The entries that named it stay, and are then about no condition.

  A read gives no episode of a resident that an administrator removed.
  """

  # The read has a filter on purpose: see the last line of the @moduledoc.
  use Rescord.Resource,
    domain: Rescord.Journal,
    authorizers: [Ash.Policy.Authorizer],
    primary_read_warning?: false

  alias Rescord.Journal

  postgres do
    table "episodes"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    read :read do
      primary? true

      description "The conditions that residents have and had: each with its resident, its condition, its first day, its last day when it is over, and whether it is chronic"

      # A removed resident is archived: its conditions are in no list.
      filter expr(exists(resident, true))
    end

    create :start do
      description "Starts a condition of a resident. A diagnosis in the journal runs it"
      accept [:resident_id, :condition_id, :started_on, :chronic, :note]

      change {Journal.Changes.EpisodeDay, attribute: :started_on}
      validate Journal.Validations.EpisodeDays
    end

    update :resolve do
      description "Marks a condition of a resident as resolved, with its last day: today when none is given"
      require_atomic? false
      accept [:ended_on]

      change {Journal.Changes.EpisodeDay, attribute: :ended_on}
      validate Journal.Validations.EpisodeDays
    end

    update :reopen do
      description "Opens a resolved condition of a resident again: it was not over"
      accept []
      change set_attribute(:ended_on, nil)
    end

    update :revise do
      description "Changes the first day, the last day, the chronic mark or the note of a condition of a resident"
      require_atomic? false
      accept [:started_on, :ended_on, :chronic, :note]

      validate Journal.Validations.EpisodeDays
    end

    update :rename do
      description "Gives an episode another condition. The correction of its one diagnosis runs it"
      accept [:condition_id]
    end

    destroy :remove do
      description "Removes a condition of a resident that was recorded by mistake. Its entries stay, about no condition"
      # The change writes other records before the removal.
      require_atomic? false
      change Journal.Changes.ReleaseEntries
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

    attribute :started_on, :date do
      allow_nil? false
      public? true
      description "The first day of the condition"
    end

    attribute :ended_on, :date do
      public? true
      description "The last day of the condition. Empty while the condition is ongoing"
    end

    attribute :chronic, :boolean do
      allow_nil? false
      default false
      public? true
      description "Whether the resident keeps the condition"
    end

    attribute :note, :string do
      public? true
      constraints max_length: 200

      description "A few words about this condition of this resident, such as the foot that has it"
    end
  end

  relationships do
    belongs_to :resident, Rescord.Residents.Resident do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :condition, Rescord.Lists.Condition do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :entries, Journal.JournalEntry do
      public? true
      destination_attribute :episode_id
      temporal_keys {:valid_at, :valid_at}
    end
  end

  calculations do
    calculate :state,
              Journal.EpisodeState,
              expr(if is_nil(ended_on), do: :ongoing, else: :resolved) do
      public? true
      description "Whether the condition is ongoing or resolved"
    end

    calculate :condition_label, :ci_string, expr(condition.label) do
      public? true
      description "The name of the condition"
    end

    calculate :resident_name, :string, expr(resident.name) do
      public? true
      description "The name of the resident at the instant of the read"
    end
  end

  aggregates do
    count :entry_count, :entries do
      public? true
      description "The number of journal entries about the condition"
    end
  end
end
