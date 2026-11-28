defmodule RescordWeb.UsagePagesTest do
  @moduledoc """
  The page of the usage counts, `/root/usage` (ADR 0098): who opens it,
  the mode and the address, the token that no page shows, the test, the
  document, the counts, and that a page and a file count. The tests find
  what a person finds (ADR 0107).

  Not async: the counts of the memory and the mode are of the node.
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [render_async: 1]
  import Rescord.AccountsFixtures

  alias Rescord.Usage
  alias Rescord.Usage.{Counter, Settings}

  @mode {Rescord.Usage, :mode}
  @token "a-token-that-no-page-shows"

  setup context do
    :persistent_term.erase(@mode)
    on_exit(fn -> :persistent_term.erase(@mode) end)
    root = root!()
    {:ok, root: root, conn: sign_in(context.conn, root)}
  end

  defp stand, do: main() |> region("Where the counts stand")
  defp document, do: main() |> region("What Rescord sends")
  defp counts, do: main() |> region("The last 30 days")

  test "only a root user opens it", %{conn: conn} do
    build_conn() |> visit(~p"/root/usage") |> assert_path("/")
    build_conn() |> sign_in(user!()) |> visit(~p"/root/usage") |> assert_path("/")

    conn
    |> visit(~p"/root/usage")
    |> assert_path(~p"/root/usage")
    |> assert_has(stand())
  end

  test "a new server counts on the server and sends nothing", %{conn: conn} do
    session = visit(conn, ~p"/root/usage")

    assert text(session, stand() |> definition("Mode")) ==
             "Counted on this server, and sent nowhere"

    session
    |> assert_has(document(), text: "No full day has a count yet")
    |> assert_has(document(), text: "resourceMetrics")

    conn
    |> visit(~p"/root")
    |> assert_has(main(), text: "Usage counts: Counted on this server, and sent nowhere")
  end

  test "a root user turns sending on, with an address and a token", %{conn: conn, root: root} do
    conn
    |> visit(~p"/root/usage")
    |> choose("Count, and send each day")
    |> choose("OpenTelemetry (OTLP, JSON over HTTP)")
    |> fill_in("Address", with: "")
    |> click(button("Save"))
    |> assert_has(main() |> region("Where the counts go"),
      text: "give the address that gets the counts"
    )
    |> fill_in("Address", with: "https://collector.example.org/v1/metrics")
    |> choose("The plain document of Rescord")
    |> click(button("Save"))
    |> tap(fn _session ->
      assert %Settings{mode: :send, format: :json} = Usage.settings(actor: root)
      assert Usage.mode() == :send
    end)
    |> fill_in("A new token", with: @token)
    |> click(button("Save the token"))
    |> assert_has(main() |> region("The token"), text: "Ends in hows")
    |> refute_has("*", text: @token)
    |> assert_has(document(), text: ~s("schema": "rescord.usage/1"))
  end

  test "Send a test says what the address answered", %{conn: conn, root: root} do
    {:ok, _settings} =
      Usage.save_settings(%{endpoint: "https://collector.example.org/v1/metrics"}, actor: root)

    # The test runs in a task of the page.
    Req.Test.set_req_test_to_shared()
    on_exit(&Req.Test.set_req_test_to_private/0)
    Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 401, ""))

    conn
    |> visit(~p"/root/usage")
    |> click(button("Send a test"))
    |> unwrap(&render_async/1)
    |> assert_has(main() |> region("Send a test") |> status(),
      state: "alert",
      text: "The address answered 401"
    )
  end

  test "the counts of the last 30 days, by feature", %{conn: conn} do
    today = Date.utc_today()
    Usage.add_count!(Date.add(today, -1), :tools, :page, "dose", 3, authorize?: false)
    Usage.add_count!(Date.add(today, -2), :tools, :action, "tools.x.y", 2, authorize?: false)

    session = visit(conn, ~p"/root/usage")

    # The feature, the pages opened, the actions and the files.
    assert text(session, counts() |> row(~r/^Feature\b/)) == "Feature Pages opened Actions Files"
    assert text(session, counts() |> row(~r/^Tools\b/)) == "Tools 3 2 0"

    # The document of the last full day with a count.
    assert_has(session, document(), text: ~s("dose"))
  end

  test "a page that connects counts, with the name of its module", %{conn: conn} do
    Counter.take_all()
    visit(conn, ~p"/root/usage")

    assert [1] ==
             for({{_day, :server, :page, "root_usage"}, n} <- Counter.take_all(), do: n)
  end

  test "the mode off counts no page", %{conn: conn, root: root} do
    {:ok, _settings} = Usage.save_settings(%{mode: :off}, actor: root)
    Counter.take_all()
    visit(conn, ~p"/root/usage")
    assert [] == for({{_day, :server, :page, "root_usage"}, n} <- Counter.take_all(), do: n)
  end

  test "deleting the counts empties the table", %{conn: conn} do
    Usage.add_count!(Date.utc_today(), :tools, :page, "dose", 3, authorize?: false)

    conn
    |> visit(~p"/root/usage")
    |> assert_has(counts() |> table(nil))
    |> click(button("Delete the counts"))
    |> assert_has(status(), text: "Each count is deleted")
    |> assert_has(counts(), text: "No count yet")
    |> refute_has(counts() |> table(nil))
  end
end
