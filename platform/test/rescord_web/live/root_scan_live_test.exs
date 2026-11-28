defmodule RescordWeb.RootScanLiveTest do
  @moduledoc """
  Holds the page of the virus scan, `/root/scan` (issue 37): only a root
  user opens it; "Test" sends `PING` to the address in the form, saved or
  not; and a save turns the scan on. The clamd is a fake
  (`Rescord.FakeClamd`).

  The tests find what a person finds (ADR 0107).
  """

  use RescordWeb.ConnCase, async: false
  use RescordWeb.Roles

  import Phoenix.LiveViewTest, only: [live: 2]
  import Rescord.AccountsFixtures

  alias Rescord.FakeClamd
  alias Rescord.Storage.Scan

  test "a root user tests the address, and turns the scan on", %{conn: conn} do
    address = FakeClamd.start(:clean)

    session =
      conn
      |> sign_in(root!())
      |> visit(~p"/root/scan")
      |> assert_has(heading("Virus scan"))
      |> assert_has(main(), text: "Off")
      |> fill_in("Address of clamd", with: FakeClamd.nobody())
      |> click_button("Test")
      |> assert_has(status(), text: "No answer")
      |> assert_has(status(), text: "cannot be reached")
      |> fill_in("Address of clamd", with: address)
      |> click_button("Test")
      |> assert_has(status(), text: "clamd at #{address} answers.")

    refute Scan.on?()

    session
    |> check("Scan each PDF")
    |> click_button("Save")
    |> assert_has(main(), text: "On")

    assert Scan.on?()
    assert Scan.settings().address == address
  end

  test "an address that clamd cannot have is refused in words", %{conn: conn} do
    conn
    |> sign_in(root!())
    |> visit(~p"/root/scan")
    |> fill_in("Address of clamd", with: "clamd")
    |> click_button("Save")
    |> assert_has(alert(), text: "give host:port")

    refute Scan.on?()
  end

  test "is for a root user alone", %{conn: conn} do
    assert {:error, {:redirect, _}} =
             live(sign_in(conn, user!()), ~p"/root/scan")

    assert {:error, {:redirect, _}} = live(conn, ~p"/root/scan")
  end
end
