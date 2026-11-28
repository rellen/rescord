defmodule RescordWeb.MailPreviewControllerTest do
  @moduledoc """
  The pages that show each email to a developer (ADR 0070). The router has
  them with `dev_routes` alone, so the tests call the controller.
  """

  use RescordWeb.ConnCase, async: true

  alias RescordWeb.MailPreviewController

  defp call(conn, action, params) do
    conn
    |> bypass_through(RescordWeb.Router, :browser)
    |> get("/")
    |> Map.put(:params, params)
    |> MailPreviewController.call(MailPreviewController.init(action))
  end

  test "the list names each email, with a link to each part", %{conn: conn} do
    doc = conn |> call(:index, %{}) |> html_response(200) |> LazyHTML.from_document()
    links = doc |> LazyHTML.query("main li a") |> LazyHTML.attribute("href")

    for {name, email} <- Rescord.Mail.previews() do
      assert LazyHTML.text(doc) =~ email.subject
      assert "/dev/mail/#{name}/html" in links
      assert "/dev/mail/#{name}/text" in links
    end
  end

  test "the HTML part is the email as it is sent, and may load nothing", %{conn: conn} do
    {name, email} = hd(Rescord.Mail.previews())
    conn = call(conn, :show, %{"name" => name, "part" => "html"})

    assert html_response(conn, 200) == email.html_body

    assert get_resp_header(conn, "content-security-policy") == [
             "default-src 'none'; style-src 'unsafe-inline'"
           ]
  end

  test "the text part is plain text", %{conn: conn} do
    {name, email} = hd(Rescord.Mail.previews())
    conn = call(conn, :show, %{"name" => name, "part" => "text"})

    assert text_response(conn, 200) == email.text_body
  end

  test "an email that is not there is not found", %{conn: conn} do
    assert conn |> call(:show, %{"name" => "none", "part" => "html"}) |> text_response(404)
    assert conn |> call(:show, %{"name" => "invitation", "part" => "pdf"}) |> text_response(404)
  end
end
