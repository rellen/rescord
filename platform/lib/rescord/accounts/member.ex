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
  person asks for a sign-in link, as each user does. The invitation emits
  `:member_invited`, and this resource listens in a job, which sends the
  email after the commit and again after a fault (ADR 0067).

  What a role can do is in `Rescord.Accounts.Grants`, and the policy of this
  resource is the one check `Rescord.Accounts.Checks.Granted`. A root user is
  outside the grants.

  This resource is not temporal: an organisation has one member for a user at
  each time. A removed member is archived, so the user can be invited again.

  ## An erased member

  An erasure on request (ADR 0105) keeps the archived row, with `erased_at`
  and `former_number`: each page then names the person "Former member N",
  and N is the next number of the organisation, never used again. When an
  expense younger than the money period names the person, the row holds
  their email in `held_email`, encrypted with AshCloak, until `held_until`:
  the pages of the expenses show it, and a daily job lets it go.
  `Rescord.Privacy` runs `erase`, and no role has a grant for it. A person
  erased here is not invited here again with the same account.
  """

  use Rescord.Resource,
    domain: Rescord.Accounts,
    temporal?: false,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  postgres do
    table "members"
    identity_wheres_to_sql unique_user: "archived_at IS NULL"
  end

  cloak do
    # A function, so that AshCloak asks for no vault of the package `cloak`.
    vault(fn _resource, _context -> Rescord.Vault end)
    attributes([:held_email])
    encrypt_nil?(false)
  end

  paper_trail do
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
    ignore_attributes [:encrypted_held_email]
  end

  # A removed member is archived. `:with_former` reads them too, so a page
  # can still say who wrote a record (ADR 0105).
  archive do
    exclude_read_actions [:with_former]
  end

  actions do
    defaults [:read]

    read :with_former do
      description "The members of the organisation, and the members who were removed from it"
    end

    create :invite_member do
      description "Invites a person to the organisation, with the role `role_id` or the role of a member"
      argument :email, :ci_string, allow_nil?: false
      argument :role_id, :uuid
      change {Rescord.Accounts.Changes.SetRole, key: :member}
      validate Rescord.Accounts.Validations.WithinPowers, before_action?: true
      change Rescord.Accounts.Changes.Invite

      emit Rescord.Accounts.Signals, :member_invited,
        values: [email: arg(:email), invited_by: actor(:email)]
    end

    create :invite_administrator do
      description "Invites a person to the organisation as an administrator"
      argument :email, :ci_string, allow_nil?: false
      change {Rescord.Accounts.Changes.SetRole, key: :administrator}
      change Rescord.Accounts.Changes.Invite

      emit Rescord.Accounts.Signals, :member_invited,
        values: [email: arg(:email), invited_by: actor(:email)]
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
      description "Takes the member out of the organisation. The records of the member stay theirs, marked as a former member"
      require_atomic? false
      validate Rescord.Accounts.Validations.NotTheLastManager

      # Tasks, routines and calendar feeds let go of the person (ADR 0105).
      emit Rescord.Accounts.Signals, :member_removed, fields: [user_id: :user_id]
    end

    update :erase do
      description "Pseudonymises an archived member as Former member N, and holds the email for the money records until `held_until`. Only `Rescord.Privacy` runs it"
      accept [:held_email, :held_until]
      argument :keep_comments, :boolean, allow_nil?: false, default: false
      # The number of a marker, when an erasure runs again after a restore.
      argument :former_number, :integer, constraints: [min: 1]
      require_atomic? false

      validate attribute_does_not_equal(:archived_at, nil),
        message: "is a member: remove the member first"

      validate attribute_equals(:erased_at, nil), message: "is erased already"
      change Rescord.Accounts.Changes.Pseudonymise

      # Ruby, calendars and comments let go of the person (ADR 0105).
      emit Rescord.Accounts.Signals, :member_erased,
        fields: [user_id: :user_id, former_number: :former_number],
        values: [keep_comments: arg(:keep_comments)]
    end

    update :release_hold do
      description "Lets go of the email that an erased member held for the money records. A daily job runs it"
      accept []
      require_atomic? false
      change set_attribute(:encrypted_held_email, nil)
      change set_attribute(:held_until, nil)
    end

    read :held_before do
      description "The erased members whose hold ended before a day. A daily job runs it"
      argument :day, :date, allow_nil?: false
      filter expr(not is_nil(erased_at) and held_until < ^arg(:day))
    end

    action :send_invitation do
      description "Sends the email of an invitation. A job runs this for `:member_invited`, and no role has a grant for it"

      # Not the struct as the type: AshBoundary exports a type that a public
      # resource names, and `boundary` does not know a struct that a signal
      # module generates (ADR 0067).
      argument :signal, :struct,
        allow_nil?: false,
        constraints: [instance_of: Rescord.Accounts.Signals.MemberInvited]

      run Rescord.Accounts.Actions.SendInvitation
    end
  end

  policies do
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    policy always() do
      # The job of an invitation has no person: the invitation was the
      # decision (ADR 0067).
      authorize_if signal_in(Rescord.Accounts.Signals, :member_invited)
      authorize_if Rescord.Accounts.Checks.Granted
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :erased_at, :utc_datetime_usec do
      public? true
      writable? false
      description "When the member was erased on request (ADR 0105)"
    end

    attribute :former_number, :integer do
      public? true
      writable? false
      constraints min: 1

      description "The N of Former member N, after an erasure. Unique in the organisation, and never used again"
    end

    # AshCloak takes this attribute away, and makes the attribute
    # `encrypted_held_email` and the calculation `held_email`.
    attribute :held_email, :string do
      sensitive? true
      constraints max_length: 254
    end

    attribute :held_until, :date do
      public? true
      description "The last day that an expense needs the email of the erased member"
    end
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

  # The email of an invitation goes in a job: Oban writes the job in the
  # transaction of the invitation, runs it after the commit, and runs it
  # again after a fault. Oban waits longer before each try, so 16 tries
  # take about 18 hours (ADR 0067).
  signals_in do
    from Rescord.Accounts.Signals do
      on :member_invited, :send_invitation,
        delivery: {AshOban.Signals, queue: :default, max_attempts: 16}
    end
  end

  calculations do
    calculate :email, :ci_string, Rescord.Accounts.Calculations.MemberEmail do
      public? true
      description "The email address of the user of the member"
    end

    calculate :former?, :boolean, expr(not is_nil(archived_at)) do
      public? true
      description "Whether the member was taken out of the organisation (ADR 0105)"
    end
  end

  identities do
    identity :unique_user, [:user_id],
      where: expr(is_nil(archived_at)),
      message: "is a member of the organisation already"

    identity :unique_former_number, [:former_number]
  end
end
