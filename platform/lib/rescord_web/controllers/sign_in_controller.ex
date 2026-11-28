defmodule RescordWeb.SignInController do
  @moduledoc """
  The pages of the sign-in by a link in an email (ADR 0018).

  `create/2` holds the rule of ADR 0019: it gives the same answer for each
  address, and it does not wait for the work. It does not look at the address
  before it hands it to `Rescord.Accounts.request_sign_in_link/1`.
  """

  use RescordWeb, :controller

  alias RescordWeb.UserAuth

  # One client can ask for 20 links in 15 minutes (ADR 0020). The count does
  # not depend on the address, so a refusal says nothing about an account.
  @client_limit 20
  @client_period :timer.minutes(15)

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign in")
  end

  def create(conn, params) do
    with {:allow, _count} <-
           Rescord.RateLimit.hit(client_key(conn), @client_period, @client_limit),
         :ok <- Rescord.Accounts.request_sign_in_link(params["email"]) do
      redirect(conn, to: ~p"/sign-in/sent")
    else
      {:deny, _wait} ->
        conn
        |> put_status(:too_many_requests)
        |> render(:too_many, page_title: "Too many requests")

      {:error, :busy} ->
        conn |> put_status(:service_unavailable) |> render(:busy, page_title: "Rescord is busy")
    end
  end

  def sent(conn, _params) do
    render(conn, :sent, page_title: "Look in your email")
  end

  # The page of the link. It does not sign the person in: a mail program can
  # open a link before the person does. The button on the page does.
  def link(conn, params) do
    conn
    # The token is in the address of this page. Keep it out of a `Referer`.
    |> put_resp_header("referrer-policy", "no-referrer")
    |> render(:link, token: params["token"], page_title: "Sign in to Rescord")
  end

  def confirm(conn, params) do
    case Rescord.Accounts.sign_in_with_link(params["token"]) do
      {:ok, user} ->
        conn
        |> UserAuth.sign_in(user)
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:expired, page_title: "This link does not work")
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.sign_out()
    |> redirect(to: ~p"/sign-in")
  end

  defp client_key(conn) do
    "sign-in/client/" <> (conn.remote_ip |> :inet.ntoa() |> to_string())
  end
end
