defmodule RescordWeb.AttachmentController do
  @moduledoc """
  Sends the file of an attachment of a journal entry, at
  `/o/<short name>/attachments/<id>` (ADR 0041).

  The person reads the attachment with their own grants, in their
  organisation, so the policy decides who gets the file. A file that the
  person cannot read, and one that is not there, get the same answer: no
  such page.

  The answer names the type that Rescord found in the first bytes of the
  file, and puts the page in a sandbox, so a file cannot run code in the
  pages of Rescord. The browser pipeline already tells the browser not to
  guess another type (`nosniff`). The browser of the person keeps the file
  for a week (`RescordWeb.FileCache`), but a journal photo of 0.1.0 that
  the job of the images has not cleaned, whose bytes will change.

  The read with the grants of the person is a second guard: the person is a
  member of the organisation before it, and each role reads the files, so
  no test can see it today. The browser
  shows a photo or a PDF, and saves it under its name.
  """

  use RescordWeb, :controller

  alias Rescord.{Accounts, Journal}
  alias RescordWeb.FileCache

  def show(conn, %{"organisation" => short_name, "id" => id}) when is_binary(id) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name),
         {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, attachment, bytes} <-
           Journal.attachment_file(id, actor: user, tenant: organisation) do
      conn
      |> put_resp_content_type(attachment.content_type, nil)
      |> put_resp_header("content-security-policy", "sandbox; default-src 'none'; img-src 'self'")
      |> FileCache.put(FileCache.stable?(attachment))
      |> put_resp_header("content-disposition", disposition(attachment.name))
      |> send_resp(200, bytes)
    else
      _no_file -> not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: RescordWeb.ErrorHTML)
    |> render(:"404")
  end

  # `inline`, with the name as plain ASCII and as UTF-8 (RFC 6266). The
  # ASCII name has no quote, no backslash and no control character.
  defp disposition(name) do
    ascii =
      name
      |> String.normalize(:nfd)
      |> String.replace(~r/[^\x20-\x7E]/u, "")
      |> String.replace(~r/["\\]/, "")
      |> case do
        "" -> "attachment"
        plain -> plain
      end

    ~s(inline; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(name, &URI.char_unreserved?/1)})
  end
end
