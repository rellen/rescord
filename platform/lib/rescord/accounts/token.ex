defmodule Rescord.Accounts.Token do
  @moduledoc """
  The tokens of AshAuthentication: a sign-in link that is in use, and a
  session.

  A token is not a fact of the domain. It has no history: it is not temporal,
  it keeps no paper trail, and AshAuthentication deletes it after it expires.
  """

  use Rescord.Resource,
    domain: Rescord.Accounts,
    shared?: true,
    temporal?: false,
    paper_trail?: false,
    archive?: false,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
