defmodule Rescord.Ruby.LLM.EnvironmentTest do
  @moduledoc """
  Ruby takes no key from the environment of the server. The key of a
  request is the key of the provider, and a provider with no key sends
  none, also when the environment holds a key for another reason.
  """
  use ExUnit.Case, async: false

  @moduletag capture_log: true

  alias Rescord.FakeAnthropic
  alias Rescord.Ruby.LLM.Profile

  @names ~w(ANTHROPIC_API_KEY OPENAI_API_KEY OLLAMA_API_KEY)
  @stray "sk-of-the-environment-not-a-key"

  setup do
    for name <- @names, do: System.put_env(name, @stray)
    on_exit(fn -> for name <- @names, do: System.delete_env(name) end)
  end

  defp send_one(profile) do
    {:ok, response} =
      ReqLLM.stream_text(
        Profile.model_spec(profile),
        [ReqLLM.Context.user("hi")],
        Profile.req_llm_opts(profile)
      )

    try do
      Enum.to_list(response.stream)
    rescue
      ReqLLM.Error.API.Stream -> :failed
    end
  end

  test "the key of the provider goes to Anthropic, and not the key of the environment" do
    {:ok, fake} = FakeAnthropic.start_link([{:text, "Hello."}])
    {:ok, profile} = Profile.from_provider(%{kind: :anthropic, api_key: "sk-test-not-a-key"})

    send_one(%{profile | base_url: FakeAnthropic.url(fake)})

    assert [%{headers: headers}] = FakeAnthropic.requests(fake)
    assert headers["x-api-key"] == "sk-test-not-a-key"
    refute inspect(headers) =~ @stray
  end

  test "a provider with no key sends none, also with a key in the environment" do
    for kind <- [:ollama, :openai_compatible] do
      {:ok, fake} = FakeAnthropic.start_link([])

      {:ok, profile} =
        Profile.from_provider(%{
          kind: kind,
          model: "m",
          base_url: FakeAnthropic.url(fake) <> "/v1"
        })

      send_one(profile)

      assert [%{path: "/v1/chat/completions", headers: headers}] = FakeAnthropic.requests(fake)
      refute Map.has_key?(headers, "authorization"), "#{kind} sent a header of authorization"
      refute inspect(headers) =~ @stray
    end
  end

  test "a hosted provider with no key makes no profile, so no request" do
    assert {:error, [api_key: _]} = Profile.from_provider(%{kind: :anthropic})

    assert {:error, [api_key: _]} =
             Profile.from_provider(%{kind: :bedrock, model: "m", region: "us-east-1"})
  end
end
