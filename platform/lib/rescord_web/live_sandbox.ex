defmodule RescordWeb.LiveSandbox do
  @moduledoc """
  Lets a LiveView of a browser test use the database transaction of that test
  (ADR 0023).

  A browser test runs its test in one process and its pages in others. The
  browser sends the transaction of the test in its `User-Agent`, and this
  hook gives the LiveView leave to use it. The router adds the hook in the
  tests only. Outside a browser test the `User-Agent` has no transaction, and
  the hook does nothing.
  """

  import Phoenix.Component, only: [assign_new: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  def on_mount(:default, _params, _session, socket) do
    socket =
      assign_new(socket, :phoenix_ecto_sandbox, fn ->
        if connected?(socket), do: get_connect_info(socket, :user_agent)
      end)

    Phoenix.Ecto.SQL.Sandbox.allow(socket.assigns.phoenix_ecto_sandbox, Ecto.Adapters.SQL.Sandbox)

    {:cont, socket}
  end
end
