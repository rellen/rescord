defmodule Rescord.Ruby.LLM.ProfileTest do
  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias Rescord.FakeAnthropic
  alias Rescord.Ruby.LLM.Profile

  @question [ReqLLM.Context.user("hi")]

  # A provider as the resource `Rescord.Ruby.Provider` holds it, with its
  # key decrypted. A test replaces what it is about.
  defp provider(values), do: Map.merge(%{kind: :anthropic, api_key: "sk-test-not-a-key"}, values)

  defp profile!(values) do
    {:ok, profile} = Profile.from_provider(values)
    profile
  end

  # ReqLLM checks the options before it connects. Nothing listens on port 1,
  # so a profile that passes the checks fails later, when the stream is read.
  defp accepted?(profile) do
    case ReqLLM.stream_text(Profile.model_spec(profile), @question, Profile.req_llm_opts(profile)) do
      {:ok, response} ->
        ReqLLM.StreamResponse.close(response)
        true

      {:error, error} ->
        flunk("ReqLLM refused the options: " <> Exception.message(error))
    end
  end

  test "ReqLLM takes the options of each kind of provider" do
    # A hosted kind takes an address with TLS only, so the test puts the
    # address of this machine into the profile after the rules passed.
    anthropic = profile!(provider(%{model: "claude-sonnet-5-5"}))
    assert accepted?(%{anthropic | base_url: "http://127.0.0.1:1"})

    assert accepted?(
             profile!(%{kind: :ollama, model: "qwen3.6:27b", base_url: "http://127.0.0.1:1/v1"})
           )

    assert accepted?(
             profile!(%{
               kind: :openai_compatible,
               model: "local-model",
               base_url: "http://127.0.0.1:1/v1"
             })
           )

    # ReqLLM makes the host of Bedrock from the region, and takes no other
    # address. A region that does not exist gives a host that no machine
    # has, so this test sends nothing to AWS.
    assert accepted?(
             profile!(%{
               kind: :bedrock,
               model: "au.anthropic.claude-sonnet-5-5",
               api_key: "bearer-token",
               region: "no-region-0"
             })
           )
  end

  test "a provider makes a profile, with the defaults of its kind" do
    assert %Profile{
             provider: :anthropic,
             model: "claude-opus-5-5",
             api_key: "sk-test-not-a-key",
             effort: :low,
             max_output_tokens: 4_096,
             context_tokens: 60_000,
             prices: {4_000_000, 20_000_000, 200_000, 8_000_000}
           } = profile!(provider(%{}))

    assert %Profile{
             provider: :ollama,
             base_url: "http://localhost:11434/v1",
             context_tokens: 32_000,
             api_key: nil,
             prices: nil
           } = profile!(%{kind: :ollama, model: "qwen3.6:27b"})

    assert %Profile{provider: :amazon_bedrock, region: "ap-southeast-2"} =
             profile!(%{
               kind: :bedrock,
               model: "au.anthropic.claude-sonnet-5-5",
               api_key: "bearer-token",
               region: "ap-southeast-2"
             })

    # What the root user typed holds over the default. An empty field of a
    # form counts as no value.
    assert %Profile{model: "claude-haiku-5-5", effort: :medium, max_output_tokens: 2_000} =
             profile!(
               provider(%{
                 model: "claude-haiku-5-5",
                 effort: :medium,
                 max_output_tokens: 2_000,
                 base_url: "",
                 region: nil
               })
             )
  end

  defmodule Row do
    @moduledoc "The attributes of `Rescord.Ruby.Provider` that a profile reads."
    defstruct [:kind, :model, :base_url, :region, :api_key, :key_set_at, :effort] ++
                [:max_output_tokens, :context_tokens, :price_input, :price_output]
  end

  test "a record works as a map does, and an attribute with no value takes the default" do
    row = %Row{kind: :anthropic, api_key: "sk-test-not-a-key", key_set_at: DateTime.utc_now()}

    assert [] = Profile.problems(row)
    assert {:hosted, _} = Profile.destination(row)

    assert {:ok, %Profile{model: "claude-opus-5-5", effort: :low, context_tokens: 60_000}} =
             Profile.from_provider(row)
  end

  test "what is wrong with a provider, by field" do
    assert [] = Profile.problems(provider(%{}))
    assert [kind: "choose the service"] = Profile.problems(%{})
    assert [kind: "choose the service"] = Profile.problems(%{kind: :azure, model: "m"})

    assert [api_key: "this service needs a key"] = Profile.problems(%{kind: :anthropic})
    assert [model: "name the model"] = Profile.problems(%{kind: :ollama})

    assert [api_key: "Ollama takes no key"] =
             Profile.problems(%{kind: :ollama, model: "m", api_key: "x"})

    assert [region: "Amazon Bedrock needs a region"] =
             Profile.problems(%{kind: :bedrock, model: "m", api_key: "x"})

    assert [base_url: "Amazon Bedrock takes no address"] =
             Profile.problems(%{
               kind: :bedrock,
               model: "m",
               api_key: "x",
               region: "us-east-1",
               base_url: "https://gateway.example.org"
             })

    assert [base_url: "this service needs an address"] =
             Profile.problems(%{kind: :openai_compatible, model: "m"})

    assert [base_url: "the address of a hosted service starts with https://"] =
             Profile.problems(provider(%{base_url: "http://proxy.example.org"}))

    assert [base_url: "the address starts with http:// or https://"] =
             Profile.problems(%{kind: :openai_compatible, model: "m", base_url: "10.0.0.5:8080"})

    assert [effort: "the effort is low, medium or high"] =
             Profile.problems(provider(%{effort: :max}))

    # The validation runs when a key is set too: the row then has an
    # address, and the form of the key has the key.
    assert [base_url: "a key goes only to an address that starts with https://"] =
             Profile.problems(%{
               kind: :openai_compatible,
               model: "m",
               base_url: "http://10.0.0.5:8080/v1",
               api_key: "x"
             })

    assert [max_output_tokens: "the limit of an answer is below the limit of a request"] =
             Profile.problems(provider(%{max_output_tokens: 8_000, context_tokens: 8_000}))

    assert [context_tokens: "the limit of a request is from 8,000 to 200,000 tokens"] =
             Profile.problems(provider(%{context_tokens: 1_000_000}))

    assert [price_output: "give both prices, or none"] =
             Profile.problems(provider(%{price_input: 1_000_000}))

    # Each problem of a form at once, so the page marks each field.
    assert [model: _, region: _, effort: _] =
             Profile.problems(%{kind: :bedrock, api_key: "x", effort: "high"})

    assert {:error, [api_key: "this service needs a key"]} =
             Profile.from_provider(%{kind: :anthropic})
  end

  test "a key never goes over plain HTTP, except to this machine" do
    local = %{kind: :openai_compatible, model: "m", base_url: "http://10.0.0.5:8080/v1"}

    # A server that asks for no key, on a private network.
    assert [] = Profile.problems(local)

    # The same with a key: in the form, or stored in the row.
    assert [base_url: _] = Profile.problems(Map.put(local, :api_key, "x"))
    assert [base_url: _] = Profile.problems(Map.put(local, :key_set_at, DateTime.utc_now()))

    # With TLS, or on this machine, a key may go.
    for url <- [
          "https://llm.example.org/v1",
          "http://localhost:8000/v1",
          "http://127.0.0.1:8000/v1"
        ] do
      assert [] = Profile.problems(%{local | base_url: url} |> Map.put(:api_key, "x"))
    end

    # A hosted service has TLS always, also on this machine.
    assert [base_url: "the address of a hosted service starts with https://"] =
             Profile.problems(provider(%{base_url: "http://localhost:4000"}))
  end

  test "a form that does not hold the key still passes, and makes no profile" do
    # The row says that a key is stored. The form of another field has no key.
    row = %{kind: :anthropic, model: "claude-sonnet-5-5", key_set_at: ~U[2026-11-27 10:00:00Z]}
    assert [] = Profile.problems(row)
    assert [] = Profile.problems(Map.put(row, :api_key, %Ash.NotLoaded{field: :api_key}))

    # A reply needs the key itself. A caller that did not open it gets no
    # profile, and so sends no request without a key.
    assert {:error, [api_key: "the key of the provider was not opened"]} =
             Profile.from_provider(row)

    assert {:error, [api_key: "the key of the provider was not opened"]} =
             Profile.from_provider(Map.put(row, :api_key, %Ash.NotLoaded{field: :api_key}))

    assert {:ok, %Profile{api_key: "sk-test-not-a-key"}} =
             Profile.from_provider(Map.put(row, :api_key, "sk-test-not-a-key"))
  end

  test "the prices of a provider" do
    # A model of the table.
    assert %Profile{prices: {2_000_000, 10_000_000, 100_000, 4_000_000}} =
             profile!(provider(%{model: "claude-sonnet-5-5"}))

    # Claude on Bedrock: the table, and a tenth more in a geography.
    bedrock = %{kind: :bedrock, api_key: "bearer-token", region: "ap-southeast-2"}

    assert %Profile{prices: {2_200_000, 11_000_000, 110_000, 4_400_000}} =
             profile!(Map.put(bedrock, :model, "au.anthropic.claude-sonnet-5-5"))

    assert %Profile{prices: {2_000_000, 10_000_000, 100_000, 4_000_000}} =
             profile!(Map.put(bedrock, :model, "global.anthropic.claude-sonnet-5-5"))

    # A model that the table does not have costs nothing, until the root
    # user gives its prices. Then each token of the prompt has the price of
    # the input.
    other = %{
      kind: :openai_compatible,
      model: "some-model",
      base_url: "https://llm.example.org/v1"
    }

    assert %Profile{prices: nil} = profile!(other)

    assert %Profile{prices: {500_000, 1_500_000, 500_000, 500_000}} =
             profile!(Map.merge(other, %{price_input: 500_000, price_output: 1_500_000}))

    # For a model of the table, the table holds: it has the prices of the
    # cache, and a price that a root user left from another model must not
    # count for this one.
    assert %Profile{prices: {4_000_000, 20_000_000, 200_000, 8_000_000}} =
             profile!(provider(%{price_input: 1, price_output: 2}))
  end

  test "inspect does not show the key" do
    profile = profile!(provider(%{api_key: "sk-secret"}))
    refute inspect(profile) =~ "sk-secret"
  end

  test "where the data goes, from a provider with no key" do
    assert {:hosted, _} = Profile.destination(%{kind: :anthropic})
    assert {:hosted, _} = Profile.destination(profile!(provider(%{})))

    # The sentences that an administrator reads before they agree. A
    # change of one is a change of what the page promises, so each is held
    # word for word.
    assert "Anthropic, in the United States and other countries" =
             Profile.place(%{kind: :anthropic})

    assert "Amazon Bedrock, from the region ap-southeast-2" =
             Profile.place(%{kind: :bedrock, region: "ap-southeast-2"})

    # Ollama with no address is on this machine.
    assert :this_server = Profile.destination(%{kind: :ollama})
    assert "this server" = Profile.place(%{kind: :ollama, model: "m"})

    assert {:address, "10.0.0.5"} =
             Profile.destination(%{
               kind: :openai_compatible,
               model: "m",
               base_url: "http://10.0.0.5:8080/v1"
             })

    # A gateway in front of Anthropic is an address too, not Anthropic.
    assert "the model at the address gateway.example.org, which a root user of this server set" =
             Profile.place(provider(%{base_url: "https://gateway.example.org"}))

    # A form that is not complete yet.
    assert :unknown = Profile.destination(%{kind: :openai_compatible})
    assert :unknown = Profile.destination(%{kind: nil})
    assert :unknown = Profile.destination(%{kind: :bedrock})
    assert "a place that is not set yet" = Profile.place(%{kind: :bedrock})
  end

  test "the key of the place, which an organisation agrees to" do
    assert "anthropic" = Profile.place_key(provider(%{}))
    assert "anthropic" = Profile.place_key(profile!(provider(%{})))

    assert "bedrock:ap-southeast-2" =
             Profile.place_key(%{kind: :bedrock, region: "ap-southeast-2"})

    assert "this_server" = Profile.place_key(%{kind: :ollama})

    assert "this_server" =
             Profile.place_key(%{kind: :openai_compatible, base_url: "http://127.0.0.1:8080/v1"})

    assert "address:http://10.0.0.5:11434/v1" =
             Profile.place_key(%{kind: :ollama, base_url: "http://10.0.0.5:11434/v1"})

    # A gateway in front of Anthropic is another place than Anthropic.
    assert "address:https://gateway.example.org" =
             Profile.place_key(provider(%{base_url: "https://gateway.example.org"}))

    # A provider that is not complete has no place.
    assert nil == Profile.place_key(%{kind: :bedrock})
    assert nil == Profile.place_key(%{kind: :openai_compatible})
  end

  test "a change of the address or of the region asks the administrator again" do
    agreed = Profile.place_key(provider(%{}))
    assert Profile.agreed?(provider(%{}), agreed)

    # The model, the limits and the key are not the place.
    assert Profile.agreed?(provider(%{model: "claude-haiku-5-5", api_key: "another"}), agreed)
    assert Profile.agreed?(provider(%{max_output_tokens: 2_000, effort: :high}), agreed)

    refute Profile.agreed?(provider(%{base_url: "https://gateway.example.org"}), agreed)
    refute Profile.agreed?(%{kind: :bedrock, region: "us-east-1"}, agreed)

    refute Profile.agreed?(
             %{kind: :bedrock, region: "us-east-1"},
             Profile.place_key(%{kind: :bedrock, region: "ap-southeast-2"})
           )

    # Another port of the same machine is another address.
    refute Profile.agreed?(
             %{kind: :ollama, base_url: "http://10.0.0.5:8080/v1"},
             Profile.place_key(%{kind: :ollama, base_url: "http://10.0.0.5:11434/v1"})
           )

    # Nobody agreed yet, or the provider is not complete.
    refute Profile.agreed?(provider(%{}), nil)
    refute Profile.agreed?(%{kind: :bedrock}, nil)
  end

  test "what goes to Ollama" do
    # The fake has no chat API of the OpenAI kind: it answers 404, and keeps
    # the request.
    {:ok, fake} = FakeAnthropic.start_link([])

    profile =
      profile!(%{
        kind: :ollama,
        model: "qwen3.6:27b",
        base_url: FakeAnthropic.url(fake) <> "/v1",
        context_tokens: 32_768
      })

    {:ok, response} =
      ReqLLM.stream_text(Profile.model_spec(profile), @question, Profile.req_llm_opts(profile))

    assert_raise ReqLLM.Error.API.Stream, fn -> Enum.to_list(response.stream) end

    assert [%{path: "/v1/chat/completions", body: body, headers: headers}] =
             FakeAnthropic.requests(fake)

    assert body["model"] == "qwen3.6:27b"
    assert body["max_tokens"] == 4_096
    assert body["options"] == %{"num_ctx" => 32_768}
    assert body["keep_alive"] == "30m"
    refute Map.has_key?(headers, "authorization")
  end
end
