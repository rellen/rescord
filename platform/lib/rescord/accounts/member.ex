defmodule Rescord.Accounts.Member do
  @moduledoc """
  A user who belongs to one organisation. The member is in the schema of the
  organisation, and names a user, who is outside it.

  A member is an administrator or a member (`docs/domain.md`, section 5.1):

    * a root user invites an administrator;
    * an administrator invites a member, and can make a member an
      administrator;
    * an administrator removes a member, and a root user removes anybody.

  No action takes the role as input: each action sets it.

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
      description "Invites a person to the organisation as a member"
      argument :email, :ci_string, allow_nil?: false
      change set_attribute(:role, :member)
      change Rescord.Accounts.Changes.Invite
    end

    create :invite_administrator do
      description "Invites a person to the organisation as an administrator"
      argument :email, :ci_string, allow_nil?: false
      change set_attribute(:role, :administrator)
      change Rescord.Accounts.Changes.Invite
    end

    update :make_administrator do
      accept []
      change set_attribute(:role, :administrator)
    end

    update :make_member do
      accept []
      change set_attribute(:role, :member)
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

    attribute :role, :atom do
      allow_nil? false
      default :member
      public? true
      writable? false
      constraints one_of: [:administrator, :member]
    end
  end

  relationships do
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
