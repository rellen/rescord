defmodule RescordWeb.UserAuth do
  @moduledoc """
  The session of a signed-in user.

  `fetch_current_user/2` is a plug of the browser pipeline. It reads the
  session, and assigns `:current_user`: the user, or `nil`. The session holds
  a token, and the token is valid only while Rescord stores it, so a sign-out
  ends each copy of the session.
  """

  import Plug.Conn

  alias AshAuthentication.Plug.Helpers

  @doc "Assigns `:current_user` from the session."
  def fetch_current_user(conn, _opts) do
    conn = Helpers.retrieve_from_session(conn, :rescord)
    assign(conn, :current_user, conn.assigns[:current_user])
  end

  @doc "Starts a new session for `user`, who has just signed in."
  def sign_in(conn, user) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> Helpers.store_in_session(user)
  end

  @doc "Ends the session, and revokes its token."
  def sign_out(conn) do
    conn
    |> Helpers.revoke_session_tokens(:rescord)
    |> configure_session(renew: true)
    |> clear_session()
  end
end
