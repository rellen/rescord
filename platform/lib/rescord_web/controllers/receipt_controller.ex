defmodule RescordWeb.ReceiptController do
  @moduledoc """
  Sends the file of a receipt of an expense, or the thumbnail of its photo
  (ADR 0082):

    * `/o/<short name>/receipts/<id>` for the file;
    * `/o/<short name>/receipts/<id>/thumbnail` for the thumbnail.

  The person reads the receipt with their own grants, in their
  organisation, so the policy decides who gets the file: the person of the
  expense, and a person who manages the expenses. A file that the person
  cannot read, and one that is not there, get the same answer: no such
  page.

  As for an attachment of the journal (ADR 0041), the answer names the type
  that Rescord found in the first bytes of the file, puts the page in a
  sandbox. The bytes of a receipt never change, so the browser of the
  person keeps the file for a week (`RescordWeb.FileCache`).
  """

  use RescordWeb, :controller

  alias Rescord.{Accounts, Expenses}
  alias RescordWeb.FileCache

  def show(conn, %{"organisation" => short_name, "id" => id}) when is_binary(id) do
    with {:ok, options} <- options(conn, short_name, id),
         {:ok, receipt, bytes} <- Expenses.receipt_file(id, options) do
      send_file_bytes(conn, receipt.content_type, receipt.name, bytes)
    else
      _no_file -> not_found(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  def thumbnail(conn, %{"organisation" => short_name, "id" => id}) when is_binary(id) do
    with {:ok, options} <- options(conn, short_name, id),
         {:ok, _receipt, bytes} <- Expenses.receipt_thumbnail(id, options) do
      send_file_bytes(conn, "image/webp", "thumbnail.webp", bytes)
    else
      _no_file -> not_found(conn)
    end
  end

  def thumbnail(conn, _params), do: not_found(conn)

  defp options(conn, short_name, id) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name),
         {:ok, _uuid} <- Ecto.UUID.cast(id) do
      {:ok, [actor: user, tenant: organisation]}
    else
      _no -> :error
    end
  end

  defp send_file_bytes(conn, type, name, bytes) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("content-security-policy", "sandbox; default-src 'none'; img-src 'self'")
    |> FileCache.put(true)
    |> put_resp_header("content-disposition", disposition(name))
    |> send_resp(200, bytes)
  end

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
        "" -> "receipt"
        plain -> plain
      end

    ~s(inline; filename="#{ascii}"; filename*=UTF-8''#{URI.encode(name, &URI.char_unreserved?/1)})
  end
end
