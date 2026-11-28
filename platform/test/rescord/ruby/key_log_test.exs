defmodule Rescord.Ruby.KeyLogTest do
  @moduledoc """
  No line of the log holds the key of a provider (ADR 0068), also when the
  log shows each query with its values.

  The test changes the level of the log, so it does not run beside others.
  """

  use Rescord.DataCase, async: false

  import ExUnit.CaptureLog
  import Rescord.AccountsFixtures

  alias Rescord.Ruby
  alias Rescord.Ruby.ScriptedModel

  @first "sk-test-the-first-key-of-the-log"
  @second "sk-test-the-second-key-of-the-log"

  setup do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  test "the log of each action of a provider holds no key" do
    log =
      capture_log(fn ->
        root = root!()

        provider =
          Ruby.add_provider!(%{name: "Anthropic", kind: :anthropic, api_key: @first}, actor: root)

        {:ok, provider} = Ruby.set_provider_key(provider, @second, actor: root)

        ScriptedModel.script([{:text, "pong"}, {:error, %{status: 401, reason: @second}}])
        {:ok, provider} = Ruby.test_provider(provider, actor: root)
        {:ok, provider} = Ruby.test_provider(provider, actor: root)

        # A refused action, with the key in its input.
        {:error, _error} = Ruby.set_provider_key(provider, @first, actor: nil)
        {:error, _error} = Ruby.add_provider(%{kind: :ollama, api_key: @first}, actor: root)

        :ok = Ruby.remove_provider(provider, actor: root)
      end)

    # The log did hold the queries, so the test looked at something.
    assert log =~ "ruby_providers"
    refute log =~ @first
    refute log =~ @second
  end
end
