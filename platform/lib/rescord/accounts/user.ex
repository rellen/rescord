defmodule Rescord.Accounts.User do
  @moduledoc """
  A person who can sign in to Rescord. All organisations share the users.

  A user signs in with a link by email, and has no password (ADR 0018). The
  strategy makes no user: a user exists only after an invitation.

  ## Why this resource is not temporal

  Nobody has tested AshAuthentication on a temporal resource, and its actions
  declare no change as temporal safe (ADR 0012). The history of a user is in
  its paper trail.

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
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
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
