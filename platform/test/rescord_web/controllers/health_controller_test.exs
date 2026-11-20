defmodule RescordWeb.HealthControllerTest do
  @moduledoc """
  Holds the health endpoint (ADR 0044): `ok` while the database answers,
  with no session and no page.
  """

  use RescordWeb.ConnCase, async: true

  test "answers ok while the database answers", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert response(conn, 200) == "ok"
    assert get_resp_header(conn, "set-cookie") == []
  end
end
