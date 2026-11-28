defmodule RescordWeb.Features.ObanWebTest do
  @moduledoc """
  Oban Web works under the policy of its pages (ADR 0115), in a real
  browser: its inline script runs with the nonce of the response, and its
  page connects. `RescordWeb.ObanWebTest` holds who opens it, with
  requests; only a browser runs the script.

  Oban Web reads an Oban that runs, so the test runs one of its own, as
  `RescordWeb.ObanWebTest` does. Not async: the instance of Oban is of the
  node, and the test reads an email.
  """

  use RescordWeb.FeatureCase, async: false

  test "a root user opens Oban Web, and its script runs under the policy", %{conn: session} do
    running_oban()
    address = "root.oban@wattle-creek.example.org"
    root!(address)

    session
    |> sign_in_with_link(address)
    |> visit("/root/oban/queues")
    |> assert_connected()
    # The inline script of the head sets the width of the side bar. A
    # policy that refused it would leave the property empty.
    |> evaluate(
      ~s|document.documentElement.style.getPropertyValue("--sidebar-width")|,
      fn width -> assert width == "320px" end
    )
  end

  # An Oban that runs, in place of the one of the tests, for this test.
  defp running_oban do
    :ok = Supervisor.terminate_child(Rescord.Supervisor, Oban)
    on_exit(fn -> {:ok, _pid} = Supervisor.restart_child(Rescord.Supervisor, Oban) end)

    start_supervised!(
      {Oban,
       name: Oban,
       repo: Rescord.Repo,
       testing: :disabled,
       queues: false,
       plugins: false,
       peer: false,
       notifier: Oban.Notifiers.PG,
       stage_interval: :infinity}
    )
  end
end
