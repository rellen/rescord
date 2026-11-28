defmodule RescordWeb.LogTest do
  @moduledoc """
  Holds what the log of a request and of a page holds (ADR 0077): the id of
  the user and of the organisation, and nothing that a person typed when a
  page stops with a fault.
  """

  use RescordWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures

  defmodule Stops do
    @moduledoc false
    use Phoenix.LiveView

    def mount(_params, _session, socket), do: {:ok, socket}

    def render(assigns) do
      ~H"""
      <form id="note" phx-submit="save"><input name="note" /><button>Save</button></form>
      """
    end

    def handle_event("save", _params, _socket), do: raise("no room")
    def handle_info({:record, _record}, _socket), do: raise("no room")
  end

  setup do
    before = Logger.metadata()
    Logger.reset_metadata()
    on_exit(fn -> Logger.reset_metadata(before) end)
  end

  test "a request names its user and its organisation in the log", %{conn: conn} do
    root = root!()
    organisation = organisation!(root, "Wattle Creek")
    {_member, user} = member!(organisation, :member, root)

    conn = conn |> sign_in(user) |> get(~p"/o/#{organisation.short_name}")

    assert html_response(conn, 200)
    assert Logger.metadata()[:user] == user.id
    assert Logger.metadata()[:organisation] == organisation.id
  end

  test "a request with no sign-in names nobody", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")

    assert html_response(conn, 200)
    assert Logger.metadata()[:user] == nil
    assert Logger.metadata()[:organisation] == nil
  end

  test "a page that stops in an event does not write the form of the person", %{conn: conn} do
    Process.flag(:trap_exit, true)
    {:ok, view, _html} = live_isolated(conn, Stops)

    log =
      capture_log(fn ->
        catch_exit(
          view
          |> form("#note", %{note: "the note that a person typed"})
          |> render_submit()
        )

        Process.sleep(100)
      end)

    assert log =~ "(RuntimeError) no room"
    assert log =~ "RescordWeb.LogTest.Stops.handle_event/3"
    assert log =~ "Last message: %Phoenix.Socket.Message{}"
    refute log =~ "typed"
  end

  test "a page that stops on a message does not write the message", %{conn: conn} do
    Process.flag(:trap_exit, true)
    {:ok, view, _html} = live_isolated(conn, Stops)
    reference = Process.monitor(view.pid)

    log =
      capture_log(fn ->
        send(view.pid, {:record, %{name: "Fern", email: "fern@example.org"}})
        assert_receive {:DOWN, ^reference, :process, _pid, _reason}
        Process.sleep(100)
      end)

    assert log =~ "Last message: {:record, map(2)}"
    refute log =~ "Fern"
    refute log =~ "fern@example.org"
  end
end
