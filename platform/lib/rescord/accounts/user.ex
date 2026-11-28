defmodule Rescord.Accounts.User do
  @moduledoc """
  A person who can sign in to Rescord. All organisations share the users.

  A user signs in with a link by email, and has no password (ADR 0018). The
  strategy makes no user: a user exists only after an invitation.

  ## Why this resource is not temporal

  Nobody has tested AshAuthentication on a temporal resource, and its actions
  declare no change as temporal safe (ADR 0012). The history of a user is in
  its paper trail.

  ## The root user

  A root user manages Rescord itself, and can do anything in each
  organisation (`docs/domain.md`, section 5.1). `root?` says that a user is
  one. No action accepts it as input: `make_root` and `revoke_root` set it,
  and only a root user can run them. The first root user comes from
  `Rescord.Accounts.bootstrap_root/1`.

  ## An erased user

  An erasure of the account (ADR 0105) keeps the row, with no email and
  with `erased_at`: many versions name the id, and the records of each
  organisation keep it under "Former member N". The row names nobody, and
  nobody signs in with it: a sign-in link goes to an email, and the row has
  none. A check of the database holds that `email` is empty exactly when
  `erased_at` is set. A root user is never erased.

  ## The limit on the requests for a link

  One address gets no more than 5 links in 15 minutes (ADR 0020). The limit
  counts each address, whether Rescord knows it or not, so the count says
  nothing about an account.
  """

  use Rescord.Resource,
    domain: Rescord.Accounts,
    shared?: true,
    temporal?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, AshRateLimiter]

  postgres do
    table "users"

    check_constraints do
      check_constraint :email, "email_exactly_when_not_erased",
        check: "(email IS NULL) = (erased_at IS NOT NULL)",
        message: "is empty exactly when the user is erased"
    end
  end

  authentication do
    tokens do
      enabled? true
      token_resource Rescord.Accounts.Token
      # A session is valid only while its token is stored, so a sign-out ends it.
      store_all_tokens? true
      require_token_presence_for_authentication? true

      signing_secret fn _, _ ->
        Application.fetch_env(:rescord, :token_signing_secret)
      end
    end

    strategies do
      magic_link do
        identity_field :email
        token_lifetime {15, :minutes}
        single_use_token? true
        # A mail program can open a link before the person does. The page of
        # the link therefore asks for a press of a button.
        require_interaction? true
        sender Rescord.Accounts.User.Senders.SendSignInLink
      end
    end
  end

  rate_limit do
    backend Rescord.RateLimit

    action :request_magic_link,
      limit: 5,
      per: :timer.minutes(15),
      key: &__MODULE__.address_key/1
  end

  paper_trail do
    # A version names the user who made the change.
    belongs_to_actor :user, Rescord.Accounts.User, domain: Rescord.Accounts
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      argument :email, :ci_string, allow_nil?: false
      get? true
      filter expr(email == ^arg(:email))
    end

    read :roots do
      description "The root users"
      filter expr(root? == true)
    end

    create :for_invitation do
      description "Makes the user of an invitation. Only an invitation runs it."
      accept [:email]
    end

    create :bootstrap_root do
      description "Makes the first root user. Only `Rescord.Accounts.bootstrap_root/1` runs it."
      accept [:email]
      upsert? true
      upsert_identity :unique_email
      upsert_fields [:root?]
      change set_attribute(:root?, true)
    end

    update :make_root do
      description "Makes a user a root user"
      accept []
      change set_attribute(:root?, true)
    end

    update :erase do
      description "Erases the account: the email goes, and the row stays with `erased_at`. Only `Rescord.Privacy` runs it (ADR 0105)"
      accept []
      require_atomic? false
      validate attribute_equals(:root?, false), message: "is a root user: revoke root first"
      change set_attribute(:email, nil)
      change set_attribute(:erased_at, &DateTime.utc_now/0)
    end

    update :revoke_root do
      description "Makes a root user an ordinary user. The last root user stays one."
      accept []
      require_atomic? false
      validate Rescord.Accounts.Validations.NotTheLastRoot
      change set_attribute(:root?, false)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # A root user can do anything.
    bypass actor_attribute_equals(:root?, true) do
      authorize_if always()
    end

    # Any other user reads only their own record, and changes nothing.
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action_type([:create, :update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? true
      public? true
    end

    attribute :erased_at, :utc_datetime_usec do
      public? true
      writable? false
      description "When the account was erased (ADR 0105). The email is empty from then on"
    end

    attribute :root?, :boolean do
      allow_nil? false
      default false
      public? true
      # No action takes this as input: an action sets it.
      writable? false
      source :is_root
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  @doc """
  The key of the rate limit of a request for a link: one count for each
  address, without its case and the space around it.
  """
  def address_key(query) do
    address =
      query
      |> Ash.Query.get_argument(:email)
      |> to_string()
      |> String.trim()
      |> String.downcase()

    "sign-in/address/" <> address
  end
end
