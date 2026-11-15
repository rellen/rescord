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
  alias Rescord.Accounts

  @doc "Assigns `:current_user` from the session."
  def fetch_current_user(conn, _opts) do
    conn = Helpers.retrieve_from_session(conn, :rescord)
    assign(conn, :current_user, conn.assigns[:current_user])
  end

  @doc """
  The hooks of the live sessions. Each one assigns `:current_user`, or sends
  the person away.

    * `:require_root` is for the pages of a root user.
    * `:require_organisation` is for the pages below `/o/:organisation`. It
      also assigns `:organisation`, `:member` (`nil` for a root user who is
      not a member) and `:role`.

  A page that the person cannot open, and a page that is not there, give the
  same answer.
  """
  def on_mount(:require_root, _params, session, socket) do
    case user_of(session) do
      %{root?: true} = user ->
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}

      _other ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  def on_mount(:require_organisation, params, session, socket) do
    with %{} = user <- user_of(session),
         {:ok, organisation, member} <- Accounts.organisation_for(user, params["organisation"]) do
      {:cont,
       Phoenix.Component.assign(socket,
         current_user: user,
         organisation: organisation,
         member: member,
         role: Accounts.role_in(user, member)
       )}
    else
      _other -> {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  defp user_of(session) do
    case Helpers.authenticate_resource_from_session(Accounts.User, session, :rescord, []) do
      {:ok, user} -> user
      :error -> nil
    end
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
