defmodule Rescord.Accounts.Member do
  @moduledoc """
  A user who belongs to one organisation. The member is in the schema of the
  organisation, and names a user, who is outside it.

  A member has one role of the organisation, a `Rescord.Accounts.Role`
  (ADR 0040):

    * a root user invites an administrator, who has the role with the key
      `:administrator`;
    * a person with the power `:members` invites a member, with the role
      with the key `:member` or another role, and gives a member another
      role;
    * a person with the power `:members` removes a member whose role does
      not have that power, and a root user removes anybody.

  A person gives only a role whose powers their own role has
  (`Rescord.Accounts.Validations.WithinPowers`).

  An invitation makes the user when the address has none, makes the member,
  and sends an email that says where to sign in. The email has no token: the
  person asks for a sign-in link, as each user does.

  What a role can do is in `Rescord.Accounts.Grants`, and the policy of this
  resource is the one check `Rescord.Accounts.Checks.Granted`. A root user is
  outside the grants.

  This resource is not temporal: an organisation has one member for a user at
  each time. A removed member is archived, so the user can be invited again.
  """

  use Rescord.Resource,
    domain: Rescord.Accounts,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "members"
    identity_wheres_to_sql unique_user: "archived_at IS NULL"
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    create :invite_member do
      description "Invites a person to the organisation, with the role `role_id` or the role of a member"
      argument :email, :ci_string, allow_nil?: false
      argument :role_id, :uuid
      change {Rescord.Accounts.Changes.SetRole, key: :member}
      validate Rescord.Accounts.Validations.WithinPowers, before_action?: true
      change Rescord.Accounts.Changes.Invite
    end

    create :invite_administrator do
      description "Invites a person to the organisation as an administrator"
      argument :email, :ci_string, allow_nil?: false
      change {Rescord.Accounts.Changes.SetRole, key: :administrator}
      change Rescord.Accounts.Changes.Invite
    end

    update :set_role do
      description "Gives the member another role of the organisation"
      accept []
      argument :role_id, :uuid, allow_nil?: false
      require_atomic? false
      change {Rescord.Accounts.Changes.SetRole, key: nil}
      validate Rescord.Accounts.Validations.WithinPowers, before_action?: true
    end

    update :make_administrator do
      description "Gives the member the role with the key `:administrator`"
      accept []
      require_atomic? false
      change {Rescord.Accounts.Changes.SetRole, key: :administrator}
      validate Rescord.Accounts.Validations.WithinPowers, before_action?: true
    end

    update :make_member do
      description "Gives the member the role with the key `:member`"
      accept []
      require_atomic? false
      change {Rescord.Accounts.Changes.SetRole, key: :member}
    end

    destroy :remove do
      description "Takes the member out of the organisation"
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
  end

  relationships do
    belongs_to :role, Rescord.Accounts.Role do
      allow_nil? false
      public? true
      # No action takes the role as input: `SetRole` sets it.
      attribute_writable? false
    end

    belongs_to :user, Rescord.Accounts.User do
      allow_nil? false
      public? true
      # No action takes the user as input: an invitation finds the user.
      attribute_writable? false
    end
  end

  calculations do
    calculate :email, :ci_string, Rescord.Accounts.Calculations.MemberEmail do
      public? true
      description "The email address of the user of the member"
    end
  end

  identities do
    identity :unique_user, [:user_id],
      where: expr(is_nil(archived_at)),
      message: "is a member of the organisation already"
  end
end
