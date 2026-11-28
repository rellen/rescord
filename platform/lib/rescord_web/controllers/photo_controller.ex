defmodule RescordWeb.PhotoController do
  @moduledoc """
  Sends a photo of a resident, its thumbnail (ADR 0055), or its display
  file, which a page opens in place of the photo (issue 34):

    * `/o/<short name>/photos/<id>`, `/o/<short name>/photos/<id>/thumbnail`
      and `/o/<short name>/photos/<id>/display` for a photo record;
    * `/o/<short name>/attachments/<id>/thumbnail` and
      `/o/<short name>/attachments/<id>/display` for a photo of a journal
      entry. `RescordWeb.AttachmentController` sends the photo itself.

  The person reads the record with their own grants, in their organisation,
  so the policy decides who gets the file, as for an attachment
  (ADR 0041). A file that the person cannot read, and one that is not there,
  get the same answer: no such page. The answer names the type that Rescord
  found, puts the page in a sandbox, and keeps no copy in a cache.
  """

  use RescordWeb, :controller

  alias Rescord.{Accounts, Journal, Photos}

  def show(conn, params), do: send_photo(conn, params, :photo)

  def thumbnail(conn, params), do: send_photo(conn, params, :thumbnail)

  def display(conn, params), do: send_photo(conn, params, :display)

  def attachment_thumbnail(conn, params),
    do: send_attachment(conn, params, &Journal.attachment_thumbnail/2, "thumbnail.webp")

  def attachment_display(conn, params),
    do: send_attachment(conn, params, &Journal.attachment_display/2, "photo.webp")

  defp send_attachment(conn, %{"organisation" => short_name, "id" => id}, read, name)
       when is_binary(id) do
    with {:ok, options} <- options(conn, short_name, id),
         {:ok, _attachment, bytes} <- read.(id, options) do
      send_file_bytes(conn, "image/webp", name, bytes)
    else
      _no_file -> not_found(conn)
    end
  end

  defp send_attachment(conn, _params, _read, _name), do: not_found(conn)

  defp send_photo(conn, %{"organisation" => short_name, "id" => id}, which)
       when is_binary(id) do
    with {:ok, options} <- options(conn, short_name, id),
         {:ok, photo, bytes} <- Photos.photo_file(id, which, options) do
      case which do
        :photo -> send_file_bytes(conn, photo.content_type, name(photo), bytes)
        :thumbnail -> send_file_bytes(conn, "image/webp", "thumbnail.webp", bytes)
        :display -> send_file_bytes(conn, "image/webp", name(photo, "webp"), bytes)
      end
    else
      _no_file -> not_found(conn)
    end
  end

  defp send_photo(conn, _params, _which), do: not_found(conn)

  defp options(conn, short_name, id) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name),
         {:ok, _uuid} <- Ecto.UUID.cast(id) do
      {:ok, [actor: user, tenant: organisation]}
    else
      _no -> :error
    end
  end

  # The name that a browser saves the photo under: its date and its type.
  defp name(photo) do
    extension =
      case photo.content_type do
        "image/jpeg" -> "jpg"
        "image/png" -> "png"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        _other -> "bin"
      end

    name(photo, extension)
  end

  defp name(photo, extension), do: "photo-#{Date.to_iso8601(photo.taken_on)}.#{extension}"

  defp send_file_bytes(conn, type, name, bytes) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("content-security-policy", "sandbox; default-src 'none'; img-src 'self'")
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{name}"))
    |> send_resp(200, bytes)
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: RescordWeb.ErrorHTML)
    |> render(:"404")
  end
end
