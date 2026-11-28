defmodule RescordWeb.UsagePagesTest do
  @moduledoc """
  The page of the usage counts, `/root/usage` (ADR 0098): who opens it,
  the mode and the address, the token that no page shows, the test, the
  document, the counts, and that a page and a file count.

  Not async: the counts of the memory and the mode are of the node.
  """

  use RescordWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
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

  test "only a root user opens it", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/root/usage")

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(user!()) |> live(~p"/root/usage")

    assert {:ok, _view, _html} = live(conn, ~p"/root/usage")
  end

  test "a new server counts on the server and sends nothing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/root/usage")
    assert html =~ "Counted on this server, and sent nowhere"
    assert html =~ "No full day has a count yet"
    assert html =~ "resourceMetrics"

    {:ok, _view, html} = live(conn, ~p"/root")
    assert html =~ "Usage counts: Counted on this server, and sent nowhere"
  end

  test "a root user turns sending on, with an address and a token", %{conn: conn, root: root} do
    {:ok, view, _html} = live(conn, ~p"/root/usage")

    html =
      view
      |> form("#usage-settings", usage: %{mode: "send", endpoint: "", format: "otlp"})
      |> render_submit()

    assert html =~ "give the address that gets the counts"

    view
    |> form("#usage-settings",
      usage: %{mode: "send", endpoint: "https://collector.example.org/v1/metrics", format: "json"}
    )
    |> render_submit()

    assert %Settings{mode: :send, format: :json} = Usage.settings(actor: root)
    assert Usage.mode() == :send

    html = view |> form("#usage-token-form", usage: %{token: @token}) |> render_submit()
    assert html =~ "Ends in hows"
    refute html =~ @token
    assert render(view) =~ "&quot;schema&quot;: &quot;rescord.usage/1&quot;"
  end

  test "Send a test says what the address answered", %{conn: conn, root: root} do
    {:ok, _settings} =
      Usage.save_settings(%{endpoint: "https://collector.example.org/v1/metrics"}, actor: root)

    # The test runs in a task of the page.
    Req.Test.set_req_test_to_shared()
    on_exit(&Req.Test.set_req_test_to_private/0)
    Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 401, ""))

    {:ok, view, _html} = live(conn, ~p"/root/usage")

    view |> element("#usage-test") |> render_click()
    assert render_async(view) =~ "The address answered 401"
  end

  test "the counts of the last 30 days, by feature", %{conn: conn} do
    today = Date.utc_today()
    Usage.add_count!(Date.add(today, -1), :tools, :page, "dose", 3, authorize?: false)
    Usage.add_count!(Date.add(today, -2), :tools, :action, "tools.x.y", 2, authorize?: false)

    {:ok, view, html} = live(conn, ~p"/root/usage")
    assert has_element?(view, "#usage-tools td", "Tools")
    assert has_element?(view, ~s(#usage-tools td[data-label="Pages opened"]), "3")
    assert has_element?(view, ~s(#usage-tools td[data-label="Actions"]), "2")
    # The document of the last full day with a count.
    assert html =~ "&quot;dose&quot;"
  end

  test "a page that connects counts, with the name of its module", %{conn: conn} do
    Counter.take_all()
    {:ok, _view, _html} = live(conn, ~p"/root/usage")

    assert [1] ==
             for({{_day, :server, :page, "root_usage"}, n} <- Counter.take_all(), do: n)
  end

  test "the mode off counts no page", %{conn: conn, root: root} do
    {:ok, _settings} = Usage.save_settings(%{mode: :off}, actor: root)
    Counter.take_all()
    {:ok, _view, _html} = live(conn, ~p"/root/usage")
    assert [] == for({{_day, :server, :page, "root_usage"}, n} <- Counter.take_all(), do: n)
  end

  test "deleting the counts empties the table", %{conn: conn} do
    Usage.add_count!(Date.utc_today(), :tools, :page, "dose", 3, authorize?: false)
    {:ok, view, _html} = live(conn, ~p"/root/usage")
    html = view |> element("#usage-forget") |> render_click()
    assert html =~ "Each count is deleted"
    assert html =~ "No count yet"
  end
end
