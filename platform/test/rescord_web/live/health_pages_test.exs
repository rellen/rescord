defmodule RescordWeb.HealthPagesTest do
  @moduledoc """
  The page of the sanity checks, `/root/health` (ADR 0114): who opens it,
  what it shows of each result, the button that runs the checks, and the
  line of `/root`. The tests find what a person finds (ADR 0107).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [live: 2, render_async: 2]
  import Rescord.AccountsFixtures

  alias Rescord.Health
  alias Rescord.Health.Checks

  setup %{conn: conn} do
    root = root!()
    {:ok, root: root, conn: sign_in(conn, root)}
  end

  test "only a root user opens it", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/root/health")

    assert {:error, {:redirect, %{to: "/"}}} =
             build_conn() |> sign_in(user!()) |> live(~p"/root/health")

    assert {:ok, _view, _html} = live(conn, ~p"/root/health")
  end

  test "a new server says that no check has run yet", %{conn: conn} do
    conn
    |> visit(~p"/root/health")
    |> assert_has(main() |> heading(level: 1), text: "Sanity checks")
    |> assert_has(region("Where the checks stand"), text: "No check has run yet")
    |> assert_has(region("What the checks look for"), text: "Hourly jobs that stopped")

    conn |> visit(~p"/root") |> assert_has(main(), text: "Sanity checks: no check has run yet")
  end

  test "the results of the server and of an organisation", %{conn: conn, root: root} do
    organisation = organisation!(root, "Wattle Creek")
    Health.run_check(Checks.Clock)
    Health.run_check(Checks.Managers)

    conn
    |> visit(~p"/root/health")
    |> assert_has(region("Where the checks stand"), text: "Each check passes")
    |> assert_has(
      region("The server") |> row(~r/^The clock of the server against the clock of the database/),
      text: "Passes"
    )
    |> assert_has(
      region("Wattle Creek (#{organisation.short_name})")
      |> row(~r/^Organisations where nobody can manage the members/),
      text: "Passes"
    )

    conn |> visit(~p"/root") |> assert_has(main(), text: "Sanity checks: each check passes")
  end

  test "a check that fails", %{conn: conn, root: root} do
    Rescord.Repo.query!("update public.users set is_root = false", [])
    Health.run_check(Checks.RootUsers)

    Rescord.Repo.query!("update public.users set is_root = true where id = $1", [
      Ecto.UUID.dump!(root.id)
    ])

    conn
    |> visit(~p"/root/health")
    |> assert_has(region("Where the checks stand"), text: "1 check fails")
    |> assert_has(region("The server") |> row(~r/^A server with no root user/), text: "Fails")
  end

  test "a root user runs each check now", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/root/health")

    view
    |> Phoenix.LiveViewTest.element("button", "Run each check now")
    |> Phoenix.LiveViewTest.render_click()

    html = render_async(view, 10_000)
    assert html =~ "Each check ran."
    assert html =~ "The clock of the server against the clock of the database"
  end

  test "a root user asks for an alert when a check fails, and sets up where it goes", context do
    conn = context.conn

    conn
    |> visit(~p"/root/health")
    |> assert_has(region("Alerts"), text: "The server sends no notifications yet")
    |> refute_has(region("This device"))
    |> check("Send me an alert when a check fails")
    |> within(region("Alerts"), &click_button(&1, "Save"))
    |> assert_has(status(), text: "Saved.")

    assert Health.watching?(actor: context.root)

    {:ok, _} = Rescord.Notifications.make_keys(actor: context.root)

    {:ok, _} =
      Rescord.Notifications.save_settings(
        %{
          contact: "mailto:ops@example.org",
          push_on: true,
          ntfy_url: "https://ntfy.example.org",
          ntfy_on: true
        },
        actor: context.root
      )

    conn
    |> visit(~p"/root/health")
    |> refute_has(region("Alerts"), text: "The server sends no notifications yet")
    |> assert_has(region("This device"))
    |> assert_has(region("Your devices"), text: "No device gets your notifications.")
    |> within(region("ntfy"), &click_button(&1, "Get notifications on ntfy"))
    |> assert_has(region("ntfy"), text: "https://ntfy.example.org/")
    |> uncheck("Send me an alert when a check fails")
    |> within(region("Alerts"), &click_button(&1, "Save"))

    refute Health.watching?(actor: context.root)
  end
end
