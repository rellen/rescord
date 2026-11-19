defmodule Rescord.Accounts.Role do
  @moduledoc """
  A role of an organisation, and the powers that it gives (ADR 0040).

  A power is one area of work, such as `:journal` or `:routines`.
  `Rescord.Accounts.Grants` turns each power into the grants of its
  actions. Each role also reads what each member reads.

  Each organisation starts with two roles, which the tenant migration of
  ADR 0040 makes:

    * the role with the key `:administrator`, which has each power;
    * the role with the key `:member`, which has the powers of a member of
      ADR 0021.

  The administrators of the organisation define more roles, and tick what
  each one may do. The rules:

    * The role with the key `:administrator` keeps the power `:roles`, so
      the organisation always has a person who can change the roles.
    * A person gives a role only the powers that their own role has
      (`Rescord.Accounts.Validations.WithinPowers`). A root user is outside
      this rule.
    * A role with a key, and a role that a member has, is not removed.

  This resource is not temporal: its history is in its paper trail.
  """

  use Rescord.Resource,
    domain: Rescord.Accounts,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  alias Rescord.Accounts.Validations

  postgres do
    table "roles"
    identity_wheres_to_sql unique_name: "archived_at IS NULL"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :define do
      description "Adds a role to the organisation, with its powers"
      accept [:name, :powers]
      change Rescord.Accounts.Changes.ShapePowers
      validate Validations.KnownPowers
      validate Validations.WithinPowers, before_action?: true
    end

    update :revise do
      description "Changes the name of a role, or its powers"
      accept [:name, :powers]
      require_atomic? false
      change Rescord.Accounts.Changes.ShapePowers
      validate Validations.KnownPowers
      validate Validations.KeepsRoles
      validate Validations.WithinPowers, before_action?: true
    end

    destroy :remove do
      description "Removes a role that no member has, and that has no key"
      require_atomic? false
      validate Validations.RoleNotInUse, before_action?: true
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

    attribute :name, :ci_string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 60
    end

    attribute :powers, {:array, :atom} do
      allow_nil? false
      default []
      public? true
      description "The powers of the role, from `Rescord.Accounts.Grants.power_keys/0`"
    end

    attribute :key, :atom do
      public? true
      writable? false
      constraints one_of: [:administrator, :member]

      description "`:administrator` or `:member` for the two roles that each organisation has, or none"
    end
  end

  relationships do
    has_many :members, Rescord.Accounts.Member do
      public? true
    end
  end

  identities do
    identity :unique_name, [:name],
      where: expr(is_nil(archived_at)),
      message: "is the name of another role"
  end
end
