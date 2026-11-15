defmodule RescordWeb.SignInLink do
  @moduledoc """
  Builds the address of a sign-in link.

  The email comes from the core, which cannot name a route (ADR 0009). The
  configuration `:sign_in_link_url` names `for_token/1`, and the sender calls it.
  """

  use RescordWeb, :verified_routes

  @doc "The address of the page that signs a person in with `token`."
  def for_token(token) when is_binary(token) do
    url(~p"/sign-in/link?#{[token: token]}")
  end
end
