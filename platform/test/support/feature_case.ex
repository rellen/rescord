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
    Shoddy.Tests.put_app_env(:swoosh, :shared_test_process, self())
    forget_sign_in_counts()
    :ok
  end

  # One client can ask for 20 sign-in links in 15 minutes (ADR 0020), and each
  # browser test is the same client. So each test starts with no count: the
  # limit must not depend on how many browser tests there are.
  defp forget_sign_in_counts do
    for {{"sign-in/client/" <> _address, _call} = key, _expires} <-
          :ets.tab2list(Rescord.RateLimit) do
      :ets.delete(Rescord.RateLimit, key)
    end

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
  Signs a person in as a person does: asks for a link on the sign-in page,
  takes the link from the email, and presses the button.
  """
  def sign_in_with_link(session, address) do
    import PhoenixTest

    session
    |> PhoenixTest.Playwright.visit("/sign-in", [])
    |> fill_in("Email address", with: address)
    |> PhoenixTest.Playwright.click_button(nil, "Send me a link", [])
    |> assert_has("h1", text: "Look in your email")

    Rescord.AccountsFixtures.wait_for_sign_in_tasks()

    link =
      receive do
        {:email, %Swoosh.Email{to: [{_name, ^address}], text_body: body}} ->
          [link] = Regex.run(~r{http\S+/sign-in/link\?token=\S+}, body)
          link
      after
        1_000 -> raise "no sign-in email for #{address}"
      end

    session
    |> PhoenixTest.Playwright.visit(link, [])
    |> PhoenixTest.Playwright.click_button(nil, "Sign in", [])
    |> assert_has("hgroup p", text: "You are signed in as #{address}.")
  end

  @doc """
  Waits until a LiveView page has its socket. `visit` and a click return
  before that, and the page does not answer an event until then.
  """
  def assert_connected(session) do
    PhoenixTest.assert_has(session, "[data-phx-main].phx-connected")
  end
end
