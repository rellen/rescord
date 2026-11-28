defmodule RescordWeb.UserAuth do
  @moduledoc """
  The session of a signed-in user.

  `fetch_current_user/2` is a plug of the browser pipeline. It reads the
  session, and assigns `:current_user`: the user, or `nil`. The session holds
  a token, and the token is valid only while Rescord stores it, so a sign-out
  ends each copy of the session.

  ## An open page

  A LiveView reads the user when it connects, and keeps it. A sign-out does
  not reach a page that is open in another tab, and a change to what a user
  is (a root user, or the role of a member) does not reach a page of that
  user. So the session names the socket of its user (`:live_socket_id`), and
  `disconnect/1` closes each socket of a user. Each page then connects
  again: with a valid session it reads the user as the user is now, and
  with no session it sends the person away.
  """

  import Plug.Conn

  alias AshAuthentication.Plug.Helpers
  alias Rescord.Accounts

  @doc "Assigns `:current_user` from the session."
  def fetch_current_user(conn, _opts) do
    conn = Helpers.retrieve_from_session(conn, :rescord)
    assign(conn, :current_user, named(conn.assigns[:current_user]))
  end

  @doc """
  A plug for the routes of a root user that are not pages of the live
  session `:root`, such as Oban Web and its files (ADR 0110). It comes after
  `fetch_current_user/2`. Anyone else goes to `/`, as the hook
  `:require_root` sends them.
  """
  def require_root(conn, _opts) do
    case conn.assigns[:current_user] do
      %{root?: true} -> conn
      _other -> conn |> Phoenix.Controller.redirect(to: "/") |> halt()
    end
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
        # A page with no organisation has the default locale (ADR 0075).
        RescordWeb.Locale.put(nil)
        {:cont, Phoenix.Component.assign(socket, :current_user, user)}

      _other ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end

  def on_mount(:require_organisation, params, session, socket) do
    with %{} = user <- user_of(session),
         {:ok, organisation, member} <- Accounts.organisation_for(user, params["organisation"]) do
      # The dates, the times and the numbers of the page have the forms of
      # the locale of the organisation (ADR 0075).
      RescordWeb.Locale.put(organisation)

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
      {:ok, user} -> named(user)
      :error -> nil
    end
  end

  # Each line of the log of this request or page names the user, by id
  # (ADR 0077).
  defp named(%{id: id} = user) do
    Rescord.Log.context(user: id)
    user
  end

  defp named(nobody), do: nobody

  @doc "Starts a new session for `user`, who has just signed in."
  def sign_in(conn, user) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> Helpers.store_in_session(user)
    |> put_session(:live_socket_id, socket_id(user.id))
  end

  @doc "Ends the session, revokes its token, and closes each open page of the user."
  def sign_out(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> disconnect(id)
      _nobody -> :ok
    end

    conn
    |> Helpers.revoke_session_tokens(:rescord)
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Closes each open page of a user. Call it after a change to what the user
  is: a root user, or the role of a member, or a member that is no more.
  """
  @spec disconnect(String.t()) :: :ok
  def disconnect(user_id) when is_binary(user_id) do
    RescordWeb.Endpoint.broadcast(socket_id(user_id), "disconnect", %{})
  end

  @doc "The id of the sockets of a user, which the session names."
  @spec socket_id(String.t()) :: String.t()
  def socket_id(user_id), do: "users_sockets:" <> user_id
end
