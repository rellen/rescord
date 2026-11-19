defmodule RescordWeb.TransferFileController do
  @moduledoc """
  The files of the transfers (ADR 0043):

    * `POST /o/<short name>/transfers/export` writes a transfer file for a
      partner on another server, and sends it as a download. The policy of
      the export decides who may, and the file is signed with the key of
      the refuge and encrypted for the partner. A refused export goes back
      to the page of the transfers with the words of the refusal.
    * `GET /o/<short name>/transfers/<id>/files/<file>` sends a photo or a
      PDF of a copy, when the person can read the transfer and the copy
      names the file, with a `sandbox` policy, as
      `RescordWeb.AttachmentController` does.

  A download goes through a controller, because a page of LiveView cannot
  send a file.
  """

  use RescordWeb, :controller

  alias Rescord.{Accounts, Transfers}

  def export(conn, %{"organisation" => short_name, "export" => %{} = fields}) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name) do
      facts = %{
        organisation_id: organisation.id,
        remote_partner_id: uuid(fields["remote_partner_id"]),
        resident_id: uuid(fields["resident_id"]),
        parts: parts(fields["parts"]),
        note: Shoddy.Strings.non_blank(fields["note"])
      }

      case Transfers.export_transfer(facts, actor: user) do
        {:ok, transfer, file} ->
          send_download(conn, {:binary, file},
            filename: file_name(transfer),
            content_type: "application/octet-stream"
          )

        {:error, error} ->
          conn
          |> put_flash(:error, Enum.join(Accounts.error_messages(error), ". "))
          |> redirect(to: ~p"/o/#{organisation.short_name}/transfers")
      end
    else
      _no -> not_found(conn)
    end
  end

  def export(conn, _params), do: not_found(conn)

  def show(conn, %{"organisation" => short_name, "id" => id, "file" => file_id}) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name),
         {:ok, _id} <- Ecto.UUID.cast(id),
         {:ok, file, bytes} <- Transfers.transfer_file(organisation, id, file_id, actor: user) do
      conn
      |> put_resp_content_type(file["content_type"] || "application/octet-stream", nil)
      |> put_resp_header("content-security-policy", "sandbox; default-src 'none'; img-src 'self'")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("content-disposition", "inline")
      |> send_resp(200, bytes)
    else
      _no_file -> not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: RescordWeb.ErrorHTML)
    |> render(:"404")
  end

  defp uuid(text) do
    case Ecto.UUID.cast(text) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp parts(list) when is_list(list) do
    for text <- list,
        {:ok, part} <- [RescordWeb.TransferWords.part_of(text)],
        uniq: true,
        do: part
  end

  defp parts(_other), do: []

  # `biscuit-2026-11-19.rescord`: the name of the resident in plain letters,
  # and the date of the export.
  defp file_name(transfer) do
    name =
      (transfer.resident_name || "resident")
      |> String.normalize(:nfd)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> case do
        "" -> "resident"
        plain -> plain
      end

    "#{name}-#{Date.to_iso8601(DateTime.to_date(transfer.sent_at))}.rescord"
  end
end
