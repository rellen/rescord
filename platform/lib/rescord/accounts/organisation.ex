defmodule Rescord.Accounts.Organisation do
  @moduledoc """
  A rescue or a refuge that uses Rescord. One organisation is one tenant.

  Each organisation has a schema of PostgreSQL of its own (ADR 0011), with
  the name `org_` and the id of the organisation. The record of the
  organisation itself is outside the schemas, with the users. When a root
  user creates an organisation, AshPostgres makes its schema and runs the
  tenant migrations in it.

  The short name is the part of the path that names the organisation:
  `/o/wattle-creek`. It has small letters, digits and hyphens.

  Only a root user reads or changes an organisation through its actions.
  Another user reaches the organisations that they belong to through
  `Rescord.Accounts.organisations_for/1`, which looks for their member.

  This resource is not temporal: its short name is unique at each time.
  """

  use Rescord.Resource,
    domain: Rescord.Accounts,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organisations"

    manage_tenant do
      template ["org_", :id]
    end
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    read :by_short_name do
      argument :short_name, :string, allow_nil?: false
      get? true
      filter expr(short_name == ^arg(:short_name))
    end

    create :create do
      accept [:name, :short_name, :time_zone]
      validate Rescord.Accounts.Validations.KnownTimeZone
    end

    update :set_time_zone do
      description "Changes the time zone of the organisation"
      # The validation reads the name of the zone in Elixir.
      require_atomic? false
      accept [:time_zone]
      validate Rescord.Accounts.Validations.KnownTimeZone
    end

    update :set_task_days_ahead do
      description "Changes how many days ahead the tasks of the routines exist"
      accept [:task_days_ahead]
    end

    update :set_transfer_parts do
      description "Changes the parts that a copy of a transferred resident holds at first"
      accept [:transfer_parts]
    end

    update :rename do
      accept [:name]
    end

    # The export of the data of an organisation (ADR 0054). The action reads
    # nothing: it is what the power `export` grants, and `Rescord.Export`
    # runs it before it reads the data, as the person who asks.
    action :export, :boolean do
      description "Allows an export of the data of the organisation"
      argument :organisation_id, :uuid, allow_nil?: false
      run fn _input, _context -> {:ok, true} end
    end
  end

  policies do
    # A root user can do anything.
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    # An administrator changes the settings of their own organisation
    # (ADR 0026 and ADR 0033). Nobody else has a policy here.
    policy action([:set_time_zone, :set_task_days_ahead, :set_transfer_parts, :export]) do
      authorize_if Rescord.Accounts.Checks.GrantedInOrganisation
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 100
    end

    attribute :short_name, :string do
      allow_nil? false
      public? true
      constraints match: ~r/\A[a-z0-9]+(-[a-z0-9]+)*\z/, max_length: 40
    end
  end

  attributes do
    attribute :time_zone, :string do
      allow_nil? false
      public? true
      constraints max_length: 64
      description "The name of the time zone of the organisation, for example Australia/Brisbane"
    end

    attribute :task_days_ahead, :integer do
      allow_nil? false
      default 14
      public? true
      constraints min: 1, max: 400
      description "How many days ahead the tasks of the routines exist"
    end

    attribute :transfer_parts, {:array, :atom} do
      allow_nil? false
      default []
      public? true
      constraints items: [one_of: [:journal, :stay, :placements, :relations, :photos]]

      description "The parts that a copy of a resident holds at first, other than the facts and the medical history (ADR 0042)"
    end
  end

  identities do
    identity :unique_short_name, [:short_name]
  end

  @doc "The name of the schema of an organisation."
  def schema(%__MODULE__{id: id}), do: "org_" <> id

  defimpl Ash.ToTenant do
    def to_tenant(organisation, _resource), do: Rescord.Accounts.Organisation.schema(organisation)
  end
end
