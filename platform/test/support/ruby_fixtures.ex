defmodule Rescord.RubyFixtures do
  @moduledoc """
  Helpers for the tests of the assistant: a provider, and the secret of the
  server for the time of one test.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Rescord.Ruby

  @doc "A text that has the shape of a key, and is none."
  def key, do: "sk-test-not-a-key"

  @doc "A root user adds a provider of Anthropic with a key."
  def provider!(root, values \\ %{}) do
    %{name: "Anthropic", kind: :anthropic, api_key: key()}
    |> Map.merge(values)
    |> Ruby.add_provider!(actor: root)
  end

  @doc """
  Gives the server another secret, and a previous one, until the test ends.
  The vault and the keys of the transfers read the same two. A test that
  calls this does not run beside others.
  """
  def secrets!(secret, previous \\ nil) do
    for module <- [Rescord.Vault, Rescord.Transfers.Keys] do
      before = Application.fetch_env!(:rescord, module)
      Application.put_env(:rescord, module, secret: secret, previous_secret: previous)
      on_exit(fn -> Application.put_env(:rescord, module, before) end)
    end

    :ok
  end
end
