defmodule RescordWeb.MailPreviewController do
  @moduledoc """
  Shows each email of Rescord with example values (ADR 0070), for a
  developer who changes a template. The router has these pages with
  `dev_routes` alone, beside the mailbox of Swoosh.

  The HTML part is served as it is sent, with a policy that loads nothing:
  an email that asks for an image, a font or a stylesheet of another host
  shows without it here.
  """

  use RescordWeb, :controller

  def index(conn, _params) do
    render(conn, :index, previews: Rescord.Mail.previews())
  end

  def show(conn, %{"name" => name, "part" => part}) do
    case {List.keyfind(Rescord.Mail.previews(), name, 0), part} do
      {{_name, email}, "html"} ->
        conn
        |> put_resp_header(
          "content-security-policy",
          "default-src 'none'; style-src 'unsafe-inline'"
        )
        |> put_root_layout(false)
        |> html(email.html_body)

      {{_name, email}, "text"} ->
        text(conn, email.text_body)

      _other ->
        conn |> put_status(:not_found) |> text("No such email.")
    end
  end
end
