defmodule RescordWeb.ExportController do
  @moduledoc """
  `POST /o/<short name>/export` sends the export of an organisation as a
  ZIP (ADR 0054), as of the end of the date `export[on]`. `Rescord.Export`
  checks the power of the person and reads as that person. A refusal, or a
  date that is not right, goes back to the page of the export with words.

  A download goes through a controller, because a page of LiveView cannot
  send a file.
  """

  use RescordWeb, :controller

  alias Rescord.Accounts

  def create(conn, %{"organisation" => short_name, "export" => %{"on" => on}})
      when is_binary(on) do
    with %{} = user <- conn.assigns[:current_user],
         {:ok, organisation, _member} <- Accounts.organisation_for(user, short_name) do
      result =
        case Date.from_iso8601(on) do
          {:ok, date} -> Rescord.Export.export(organisation, date, actor: user)
          {:error, _not_a_date} -> {:error, "The date is not a date."}
        end

      case result do
        {:ok, export} ->
          conn
          |> put_resp_header("cache-control", "private, no-store")
          |> send_download({:binary, export.zip},
            filename: export.filename,
            content_type: "application/zip"
          )

        {:error, :forbidden} ->
          back(conn, organisation, "Your role cannot export the data.")

        {:error, words} ->
          back(conn, organisation, words)
      end
    else
      _no -> not_found(conn)
    end
  end

  def create(conn, _params), do: not_found(conn)

  defp back(conn, organisation, words) do
    conn
    |> put_flash(:error, words)
    |> redirect(to: ~p"/o/#{organisation.short_name}/export")
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(html: RescordWeb.ErrorHTML)
    |> render(:"404")
  end
end
