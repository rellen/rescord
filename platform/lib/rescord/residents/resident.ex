defmodule Rescord.Residents.Resident do
  @moduledoc """
  An animal in the care of an organisation (`docs/domain.md`, section 5.2).

  The resident holds what it has one of and what needs no table of its own:
  the species, the sex, the date of birth, the size class and the coat. Each
  other fact is a resource about the resident:

    * the name and the desex status, each in a table of its own, so that each
      has a history (design rule 2);
    * the breeds, the colours and the temperaments, each a tie to a value of
      a list of the organisation;
    * the identifiers;
    * the arrival, the departure, and each absence.

  `register` and `revise` take the name, the desex status and the values of
  the ties as arguments, and `Rescord.Residents.Changes.WriteFacts` writes
  them in the same transaction. A page thus sends one form.

  ## The status

  Rescord calculates the status (ADR 0025). It does not store it:

    * `left` when the resident has a departure;
    * `expected` when it has no arrival;
    * `away` when it has an absence at the instant of the read;
    * `in_care` in each other case.

  A read as of a past instant gives the status at that instant.
  """

  use Rescord.Resource,
    domain: Rescord.Residents,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Residents

  postgres do
    table "residents"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    destroy :remove do
      description "Removes a resident that was recorded by mistake. The row and its history stay"
      # The change ends the ties of the resident after the removal. The signal
      # tells the domains that this one cannot know: the locations and the
      # tasks (ADR 0067).
      require_atomic? false
      change Residents.Changes.EndTies
      emit Residents.Signals, :resident_removed, fields: [resident_id: :id]
    end

    create :register do
      description "Records a new resident, with its facts"
      accept [:species_id, :sex, :born_on, :born_on_estimated, :size_class_id, :coat_id]

      argument :name, :string, constraints: [max_length: 80]
      argument :desex_status, Residents.DesexStatus, default: :unknown
      argument :breed_ids, {:array, :uuid}, default: []
      argument :colour_ids, {:array, :uuid}, default: []
      argument :temperament_ids, {:array, :uuid}, default: []

      # With no kind of arrival, the resident is expected.
      argument :arrival_kind, Residents.ArrivalKind
      argument :arrived_on, :date
      argument :arrival_note, :string, constraints: [max_length: 500]

      change Residents.Changes.WriteFacts
    end

    update :revise do
      description "Changes the facts of a resident. An argument that is not given changes nothing"
      # The change writes other resources after the update.
      require_atomic? false
      accept [:species_id, :sex, :born_on, :born_on_estimated, :size_class_id, :coat_id]

      argument :name, :string, constraints: [max_length: 80]
      argument :desex_status, Residents.DesexStatus
      argument :breed_ids, {:array, :uuid}
      argument :colour_ids, {:array, :uuid}
      argument :temperament_ids, {:array, :uuid}

      change Residents.Changes.WriteFacts
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

    attribute :sex, Residents.Sex do
      allow_nil? false
      default :unknown
      public? true
    end

    attribute :born_on, :date do
      public? true
      description "The date of birth. Rescord calculates the age from it"
    end

    # The name has no `?`, so the column has the same name (ADR 0027).
    attribute :born_on_estimated, :boolean do
      allow_nil? false
      default false
      public? true
    end
  end

  relationships do
    belongs_to :species, Rescord.Lists.Species do
      allow_nil? false
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :size_class, Rescord.Lists.SizeClass do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    belongs_to :coat, Rescord.Lists.Coat do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :name_record, Residents.ResidentName do
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :desex_record, Residents.ResidentDesexStatus do
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :arrival, Residents.Arrival do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :departure, Residents.Departure do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_one :absence, Residents.Absence do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :resident_breeds, Residents.ResidentBreed do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :resident_colours, Residents.ResidentColour do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :resident_temperaments, Residents.ResidentTemperament do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :identifiers, Residents.ResidentIdentifier do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    # The links to the parents of the resident, and to its young.
    has_many :parent_links, Residents.ParentLink do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :young_links, Residents.ParentLink do
      public? true
      destination_attribute :parent_id
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :family_memberships, Residents.FamilyMember do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end

    has_many :group_memberships, Residents.GroupMember do
      public? true
      temporal_keys {:valid_at, :valid_at}
    end
  end

  calculations do
    calculate :name, :string, expr(name_record.name) do
      public? true
      description "The name of the resident at the instant of the read"
    end

    calculate :desex_status, Residents.DesexStatus, expr(desex_record.status) do
      public? true
    end

    calculate :species_label, :ci_string, expr(species.label) do
      public? true
    end

    calculate :arrived_on, :date, expr(arrival.arrived_on) do
      public? true
    end

    calculate :status,
              Residents.Status,
              expr(
                cond do
                  exists(departure, true) -> :left
                  not exists(arrival, true) -> :expected
                  exists(absence, true) -> :away
                  true -> :in_care
                end
              ) do
      public? true
      description "Where the resident is in its stay, at the instant of the read"
    end
  end
end
