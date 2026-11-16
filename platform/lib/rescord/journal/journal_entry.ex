defmodule Rescord.Journal.JournalEntry do
  @moduledoc """
  One record that a member writes about a resident (`docs/domain.md`,
  section 5.6). The journal of a resident is the list of its entries, and
  the entries of a medical kind are its medical history.

  An entry has a kind, the words of the member, and the time that the thing
  happened. That time is the time of the write when the member gives none,
  and it is never after now. An entry of a medical kind can have facts of
  its own, each in a resource of `Rescord.Journal.Detail`: `write` and
  `correct` take them as arguments, and
  `Rescord.Journal.Changes.WriteDetail` writes them in the same
  transaction.

  ## Corrections

  The author of an entry, and an administrator, can correct it. A
  correction is a new version, so the paper trail keeps the entry as it
  was. Each other member writes an addendum: a new entry that names, in
  `follows`, the entry that it adds to.

  The author is the user who wrote the entry. No action takes it as input.
  """

  use Rescord.Resource,
    domain: Rescord.Journal,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Journal

  postgres do
    table "journal_entries"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :write do
      description "Writes a journal entry about a resident"
      accept [:resident_id, :kind, :note, :happened_at, :follows_id]

      argument :condition_id, :uuid
      argument :measure_kind_id, :uuid
      argument :value, :decimal
      argument :unit_id, :uuid
      argument :procedure_kind_id, :uuid
      argument :vaccine, :string
      argument :medication, :string
      argument :dose, :string
      argument :route, Journal.Route
      argument :starts_on, :date
      argument :ends_on, :date
      argument :prescription_id, :uuid
      argument :amount, :string

      change Journal.Changes.SetAuthor
      change Journal.Changes.HappenedAt
      validate Journal.Validations.KindHasItsFacts
      change Journal.Changes.WriteDetail
    end

    update :correct do
      description "Corrects a mistake in a journal entry. The paper trail keeps the entry as it was"
      # The changes write other resources after the update.
      require_atomic? false
      accept [:note, :happened_at]

      argument :condition_id, :uuid
      argument :measure_kind_id, :uuid
      argument :value, :decimal
      argument :unit_id, :uuid
      argument :procedure_kind_id, :uuid
      argument :vaccine, :string
      argument :medication, :string
      argument :dose, :string
      argument :route, Journal.Route
      argument :starts_on, :date
      argument :ends_on, :date
      argument :prescription_id, :uuid
      argument :amount, :string

      change Journal.Changes.HappenedAt
      change Journal.Changes.WriteDetail
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

    attribute :kind, Journal.EntryKind do
      allow_nil? false
      public? true
    end

    attribute :note, :string do
      public? true
      constraints max_length: 2000
    end

    attribute :happened_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      description "When the thing happened. The time of the write, when the member gives none"
    end

    # The id of the user who wrote the entry. It is a plain attribute: a user
    # is not temporal, so the database can hold no key from here to there.
    attribute :author_id, :uuid do
      allow_nil? false
      public? true
      writable? false
    end
  end

  relationships do
    belongs_to :resident, Rescord.Residents.Resident do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :follows, __MODULE__ do
      public? true
      temporal_keys {:valid_at, :valid_at}
      description "The earlier entry that this entry adds to: this entry is an addendum"
    end

    has_many :addenda, __MODULE__ do
      public? true
      destination_attribute :follows_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :diagnosis, Journal.Diagnosis do
      public? true
      destination_attribute :entry_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :measurement, Journal.Measurement do
      public? true
      destination_attribute :entry_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :procedure, Journal.Procedure do
      public? true
      destination_attribute :entry_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :vaccination, Journal.Vaccination do
      public? true
      destination_attribute :entry_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :prescription, Journal.Prescription do
      public? true
      destination_attribute :entry_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :dose, Journal.Dose do
      public? true
      destination_attribute :entry_id
      temporal_keys {:valid_at, :valid_at}
    end
  end
end
