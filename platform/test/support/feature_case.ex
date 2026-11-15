defmodule RescordWeb.FeatureCase do
  @moduledoc """
  The test case of a browser test (ADR 0023).

  A browser test drives a real Chromium against the real server, with
  `PhoenixTest.Playwright`. Its test has the tag `:playwright`, and it needs
  the driver of Playwright, which the devenv shell supplies. Without the
  driver, `test/test_helper.exs` leaves these tests out and says so.

  The pages run in processes of the server, and the email of a sign-in link
  leaves from a task (ADR 0019). No one of those is the test process. So:

    * the database: `PhoenixTest.Playwright.Case` starts the sandbox. With
      `async: false` each process shares the transaction of the test.
    * the email: this case names the test process as the one that gets each
      email of the Swoosh test adapter. That name is one for the whole
      system, so a browser test that reads an email is `async: false`.
  """

  use ExUnit.CaseTemplate

  # A test support module may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  using opts do
    quote do
      use PhoenixTest.Playwright.Case, unquote(opts)

      # The setup checks out the SQL sandbox (ADR 0006), and drives a browser.
      @moduletag :postgres
      @moduletag :playwright

      use RescordWeb, :verified_routes

      import Rescord.AccountsFixtures
      import RescordWeb.FeatureCase
    end
  end

  # This runs before the setup of `PhoenixTest.Playwright.Case`, so it does
  # not read the database.
  setup do
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)
    :ok
  end

  @doc "Drops each email that the test process has now."
  def flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  @doc """
  Waits until a LiveView page has its socket. `visit` and a click return
  before that, and the page does not answer an event until then.
  """
  def assert_connected(session) do
    PhoenixTest.assert_has(session, "[data-phx-main].phx-connected")
  end
end
