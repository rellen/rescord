defmodule Rescord.AccountsFixtures do
  @moduledoc """
  Helpers for the tests of the sign-in: a user, the tasks of the requests,
  and stand-ins for the function that builds a sign-in link.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias Rescord.Accounts

  @doc "An email address that no other test uses."
  def unique_address, do: "person-#{System.unique_integer([:positive])}@example.com"

  @doc "Makes a user. No page and no action of the sign-in can do that."
  def user!(address \\ unique_address()) do
    Ash.Seed.seed!(Accounts.User, %{email: address})
  end

  @doc "Waits until each task of a request for a sign-in link has ended."
  def wait_for_sign_in_tasks(timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_until(deadline)
  end

  defp wait_until(deadline) do
    case Task.Supervisor.children(Accounts.sign_in_tasks()) do
      [] ->
        :ok

      _running ->
        if System.monotonic_time(:millisecond) > deadline do
          raise "the tasks of the sign-in did not end"
        else
          Process.sleep(10)
          wait_until(deadline)
        end
    end
  end

  @doc "The token of the sign-in link in an email."
  def token_in(%Swoosh.Email{text_body: body}) do
    [_whole, token] = Regex.run(~r{/sign-in/link\?token=([^\s]+)}, body)
    URI.decode_www_form(token)
  end

  @doc """
  Names `module` as the function that builds a sign-in link, until the test
  ends. `watcher` is the test process, which the stand-ins write to.
  """
  def build_links_with(module, watcher) do
    before = Application.fetch_env!(:rescord, :sign_in_link_url)
    Application.put_env(:rescord, :sign_in_link_url, {module, :url})
    Application.put_env(:rescord, :sign_in_link_watcher, watcher)

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:rescord, :sign_in_link_url, before)
      Application.delete_env(:rescord, :sign_in_link_watcher)
    end)
  end

  defmodule SlowLink do
    @moduledoc """
    Builds a sign-in link only after the test lets it: a mail service that is
    slow.
    """

    def url(token) do
      watcher = Application.fetch_env!(:rescord, :sign_in_link_watcher)
      send(watcher, {:building, self()})

      receive do
        :go_on -> RescordWeb.SignInLink.for_token(token)
      after
        5_000 -> raise "the test did not let the link go on"
      end
    end
  end

  defmodule FailingLink do
    @moduledoc """
    Fails with the token in its message: a fault that would put a credential
    in the log.
    """

    def url(token) do
      watcher = Application.fetch_env!(:rescord, :sign_in_link_watcher)
      send(watcher, {:failing, token})
      raise "cannot build a link for the token #{token}"
    end
  end
end
