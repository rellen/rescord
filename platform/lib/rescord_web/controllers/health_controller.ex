defmodule RescordWeb.HealthController do
  @moduledoc """
  `GET /health` for a container or a service manager (ADR 0044): `ok` with
  the status 200 when the database answers, and `unavailable` with 503 when
  it does not. The answer says nothing else, and the request needs no
  session and no HTTPS, so a check on the same machine can reach it.
  """

  use RescordWeb, :controller

  def show(conn, _params) do
    if Rescord.healthy?(),
      do: conn |> put_resp_content_type("text/plain") |> send_resp(200, "ok"),
      else: conn |> put_resp_content_type("text/plain") |> send_resp(503, "unavailable")
  end
end
