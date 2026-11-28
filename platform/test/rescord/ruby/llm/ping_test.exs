defmodule Rescord.Ruby.LLM.PingTest do
  @moduledoc """
  The button "Test" of the page of a provider, against a server that plays
  Anthropic.
  """
  use ExUnit.Case, async: false

  alias Rescord.FakeAnthropic
  alias Rescord.Ruby.LLM.{Ping, Profile}
  alias Rescord.Ruby.ScriptedModel

  # The fake provider fails on purpose, and ReqLLM logs each failure.
  @moduletag capture_log: true

  # The real library, in place of the scripted model of each other test.
  setup do
    Application.put_env(:rescord, :ruby_llm, ReqLLM)
    on_exit(fn -> Application.put_env(:rescord, :ruby_llm, ScriptedModel) end)
  end

  defp profile(fake) do
    {:ok, profile} = Profile.from_provider(%{kind: :anthropic, api_key: "sk-test-not-a-key"})
    %{profile | base_url: FakeAnthropic.url(fake)}
  end

  test "the provider answers: the test passes, and says what it cost" do
    {:ok, fake} = FakeAnthropic.start_link([{:text, "pong"}])

    assert %{outcome: :ok, cost_microdollars: cost} = Ping.run(profile(fake))
    # The numbers of the fake, at the prices of Opus: 12 new tokens, 5,000
    # from the cache, 300 to the cache and 40 of answer.
    assert cost == 4_248

    assert [%{body: body, headers: headers}] = FakeAnthropic.requests(fake)
    assert headers["x-api-key"] == "sk-test-not-a-key"
    assert body["max_tokens"] == 64
    assert body["stream"] == true
    assert body["messages"] |> Jason.encode!() =~ "ping"
    # Nothing of a rescue is in it.
    refute Map.has_key?(body, "tools")
    refute Map.has_key?(body, "system")
  end

  test "the provider refuses the key" do
    body = %{type: "error", error: %{type: "authentication_error", message: "invalid x-api-key"}}
    {:ok, fake} = FakeAnthropic.start_link([{:status, 401, body}])

    assert %{outcome: {:error, :key_refused}, cost_microdollars: 0} = Ping.run(profile(fake))
  end

  test "nothing listens at the address" do
    {:ok, fake} = FakeAnthropic.start_link([])
    down = %{profile(fake) | base_url: "http://127.0.0.1:1"}

    assert %{outcome: {:error, :provider_down}} = Ping.run(down)
  end

  test "the test of a page goes through the scripted model too" do
    Application.put_env(:rescord, :ruby_llm, ScriptedModel)
    ScriptedModel.script([{:text, "pong"}])

    {:ok, profile} = Profile.from_provider(%{kind: :anthropic, api_key: "none"})
    assert %{outcome: :ok} = Ping.run(profile)
    assert [%{opts: opts}] = ScriptedModel.requests()
    assert opts[:max_tokens] == 64
  end
end
