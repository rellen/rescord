defmodule Rescord.Ruby.ProviderTest do
  @moduledoc """
  A provider of the assistant (ADR 0069): only a root user sets it, its
  rules are those of `Rescord.Ruby.LLM.Profile`, and its key is in no place
  but the one encrypted column (ADR 0068).
  """

  use Rescord.DataCase, async: true

  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.Ruby
  alias Rescord.Ruby.{LLM, Provider, ScriptedModel}

  setup do
    %{root: root!()}
  end

  describe "who sets a provider" do
    test "a root user adds, reads, changes and removes one", %{root: root} do
      provider = provider!(root)

      assert provider.model == "claude-opus-5-5"
      assert provider.context_tokens == 60_000
      assert provider.effort == :low
      assert provider.max_output_tokens == 4_096
      assert provider.default_allowance == 2_000
      refute provider.offered

      assert [%{id: id}] = Ruby.providers!(actor: root)
      assert id == provider.id
      assert {:ok, %{id: ^id}} = Ruby.provider(id, actor: root)

      assert {:ok, changed} =
               Ruby.change_provider(provider, %{model: "claude-sonnet-5-5", offered: true},
                 actor: root
               )

      assert changed.model == "claude-sonnet-5-5"
      assert changed.offered

      assert :ok = Ruby.remove_provider(changed, actor: root)
      assert Ruby.providers!(actor: root) == []
      assert {:ok, nil} = Ruby.provider(id, actor: root)
    end

    test "a person who is no root user reads none and changes none", %{root: root} do
      provider = provider!(root)

      for actor <- [nil, user!()] do
        assert Ruby.providers!(actor: actor) == []
        assert {:ok, nil} = Ruby.provider(provider.id, actor: actor)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Ruby.add_provider(%{name: "Mine", kind: :anthropic, api_key: key()},
                   actor: actor
                 )

        assert {:error, %Ash.Error.Forbidden{}} =
                 Ruby.change_provider(provider, %{offered: true}, actor: actor)

        assert {:error, %Ash.Error.Forbidden{}} =
                 Ruby.set_provider_key(provider, "sk-test-another-key", actor: actor)

        assert {:error, %Ash.Error.Forbidden{}} = Ruby.remove_provider(provider, actor: actor)
      end

      assert [%{offered: false, key_hint: "-key"}] = Ruby.providers!(actor: root)
    end

    test "the kind stays, and no action but two takes a key", %{root: root} do
      provider = provider!(root)

      assert {:error, %Ash.Error.Invalid{}} =
               Ruby.change_provider(provider, %{kind: :ollama}, actor: root)

      assert {:error, %Ash.Error.Invalid{}} =
               Ruby.change_provider(provider, %{api_key: "sk-test-another-key"}, actor: root)

      assert {:ok, %{api_key: opened}} = LLM.profile_of(provider)
      assert opened == key()
    end
  end

  describe "the rules of a provider" do
    test "a new provider gets what its kind has when a field is empty", %{root: root} do
      shed =
        Ruby.add_provider!(%{name: "The shed server", kind: :ollama, model: "a-model"},
          actor: root
        )

      assert shed.base_url == "http://localhost:11434/v1"
      assert shed.context_tokens == 32_000
      assert shed.key_set_at == nil
      assert Ruby.provider_problems(shed) == []
      assert Ruby.place(shed) == "this server"
    end

    test "a problem names its field", %{root: root} do
      add = fn values ->
        assert {:error, error} = Ruby.add_provider(Map.put(values, :name, "A name"), actor: root)
        Ruby.problems(error)
      end

      assert add.(%{kind: :anthropic}) == [api_key: "this service needs a key"]

      assert add.(%{kind: :ollama, model: "a-model", api_key: key()}) ==
               [api_key: "Ollama takes no key"]

      assert add.(%{kind: :bedrock, model: "a-model", api_key: key()}) ==
               [region: "Amazon Bedrock needs a region"]

      assert add.(%{kind: :openai_compatible, model: "a-model"}) ==
               [base_url: "this service needs an address"]

      assert add.(%{
               kind: :openai_compatible,
               model: "a-model",
               base_url: "http://llm.example.org/v1",
               api_key: key()
             }) == [base_url: "a key goes only to an address that starts with https://"]

      assert add.(%{kind: :anthropic, api_key: key(), max_output_tokens: 100}) ==
               [max_output_tokens: "the limit of an answer is from 256 to 32,000 tokens"]

      assert add.(%{kind: :anthropic, api_key: key(), model: "another-model", price_input: 5}) ==
               [price_output: "give both prices, or none"]

      assert add.(%{kind: :ollama}) == [model: "name the model"]
      assert [{:kind, _words}] = add.(%{kind: :another_service, model: "a-model"})
      assert {:kind, "choose the service"} in add.(%{model: "a-model"})

      assert Ruby.providers!(actor: root) == []
    end

    test "a change is held to the same rules", %{root: root} do
      provider = provider!(root)

      assert {:error, error} = Ruby.change_provider(provider, %{model: ""}, actor: root)
      assert Ruby.problems(error) == [model: "name the model"]

      assert {:error, error} =
               Ruby.change_provider(provider, %{base_url: "http://gateway.example.org"},
                 actor: root
               )

      assert Ruby.problems(error) ==
               [base_url: "the address of a hosted service starts with https://"]

      assert {:error, error} =
               Ruby.change_provider(provider, %{context_tokens: 4_000}, actor: root)

      assert [{:context_tokens, _words}] = Ruby.problems(error)
    end

    test "a key is refused for a provider whose address has no TLS", %{root: root} do
      provider =
        Ruby.add_provider!(
          %{
            name: "A server of the network",
            kind: :openai_compatible,
            model: "a-model",
            base_url: "http://10.0.0.5:8000/v1"
          },
          actor: root
        )

      assert {:error, error} = Ruby.set_provider_key(provider, key(), actor: root)

      assert Ruby.problems(error) ==
               [base_url: "a key goes only to an address that starts with https://"]

      assert [%{key_set_at: nil}] = Ruby.providers!(actor: root)
    end
  end

  describe "the key" do
    test "has a hint and a time in the clear", %{root: root} do
      provider = provider!(root)

      assert provider.key_hint == "-key"
      assert %DateTime{} = provider.key_set_at
    end

    test "a short key has no hint, which would be most of it", %{root: root} do
      provider = provider!(root, %{api_key: "short-key"})

      assert provider.key_hint == nil
      assert %DateTime{} = provider.key_set_at
    end

    test "no actor loads it, a root user too", %{root: root} do
      provider = provider!(root)

      for opts <- [[actor: root], [actor: user!()], [actor: nil], [authorize?: false]] do
        loaded =
          try do
            Ash.load(provider, :api_key, opts)
          rescue
            error -> {:raised, error}
          end

        refute match?({:ok, %{api_key: key}} when is_binary(key), loaded),
               "the key was loaded with #{inspect(opts)}"
      end

      read =
        try do
          Ruby.providers(actor: root, load: [:api_key])
        rescue
          error -> {:raised, error}
        end

      refute match?({:ok, [%{api_key: key}]} when is_binary(key), read)
    end

    # One module for each secret: the key of a provider, and the token of
    # the usage counts (ADR 0098).
    test "only one module of Rescord writes the mark that opens it" do
      marked =
        for path <- Path.wildcard("lib/**/*.{ex,heex}"),
            File.read!(path) =~ ~r/(?<![a-z_])context: %\{rescord_vault: :open\}/,
            do: path

      assert Enum.sort(marked) == ["lib/rescord/ruby/llm.ex", "lib/rescord/usage/sender.ex"]
    end

    test "is not in the record that an action returns", %{root: root} do
      provider = provider!(root)

      refute inspect(provider, limit: :infinity) =~ key()
      refute inspect(Ruby.providers!(actor: root), limit: :infinity) =~ key()
      assert {:ok, profile} = LLM.profile_of(provider)
      refute inspect(profile, limit: :infinity) =~ key()
    end

    test "a new key takes the place of the old one, and nobody tested it", %{root: root} do
      provider = provider!(root)
      ScriptedModel.script([{:text, "pong"}])
      assert {:ok, %{test_result: :ok} = tested} = Ruby.test_provider(provider, actor: root)

      assert {:ok, changed} = Ruby.set_provider_key(tested, "sk-test-another-key", actor: root)

      assert changed.key_hint == "-key"
      assert DateTime.compare(changed.key_set_at, provider.key_set_at) == :gt
      assert changed.tested_at == nil
      assert changed.test_result == nil
      assert {:ok, %{api_key: "sk-test-another-key"}} = LLM.profile_of(changed)
    end

    test "an empty key is refused, and the key stays", %{root: root} do
      provider = provider!(root)

      for empty <- ["", "   ", nil] do
        assert {:error, error} = Ruby.set_provider_key(provider, empty, actor: root)
        assert Ruby.problems(error) == [api_key: "type the key"]
      end

      assert {:ok, %{api_key: opened}} = LLM.profile_of(provider)
      assert opened == key()
    end

    test "a removal empties it, and keeps the row", %{root: root} do
      provider = provider!(root, %{api_key: "sk-test-a-key-to-remove"})
      assert :ok = Ruby.remove_provider(provider, actor: root)

      assert %{rows: [[nil, nil, nil, false, archived_at]]} =
               Repo.query!(
                 "select encrypted_api_key, key_hint, key_set_at, offered, archived_at from ruby_providers"
               )

      assert archived_at != nil
      refute Ruby.any_provider?()
    end
  end

  describe "where a key is kept" do
    test "the encrypted form is in one column, and the key is nowhere", %{root: root} do
      secret = "sk-test-a-key-that-is-looked-for"
      provider = provider!(root, %{api_key: "sk-test-the-first-key"})
      {:ok, _provider} = Ruby.set_provider_key(provider, secret, actor: root)

      [[encrypted]] = Repo.query!("select encrypted_api_key from ruby_providers").rows
      # AshCloak keeps the value of the vault as Base64.
      assert {:ok, sealed} = Base.decode64(encrypted)
      assert Rescord.Vault.current?(sealed)

      forms = [secret, encrypted, sealed, Base.encode16(encrypted, case: :lower)]

      [[row]] =
        Repo.query!("select (to_jsonb(p) - 'encrypted_api_key')::text from ruby_providers p").rows

      versions =
        Repo.query!("select to_jsonb(v)::text from ruby_providers_versions v").rows

      assert length(versions) == 2

      for text <- [row | List.flatten(versions)], form <- forms do
        refute text =~ form
      end
    end

    test "the version of a new key says that a key was set, and no more", %{root: root} do
      provider = provider!(root)
      {:ok, _provider} = Ruby.set_provider_key(provider, "sk-test-another-one", actor: root)

      versions =
        Provider.Version
        |> Ash.Query.sort(:version_inserted_at)
        |> Ash.read!(authorize?: false)

      assert [%{version_action_name: :add}, %{version_action_name: :set_key} = version] = versions
      assert version.user_id == root.id

      assert Enum.sort(Map.keys(version.changes)) -- ["updated_at"] ==
               ["key_hint", "key_set_at"]
    end

    test "no person reads a version", %{root: root} do
      provider!(root)

      for actor <- [root, user!(), nil] do
        assert Ash.read!(Provider.Version, actor: actor) == []
      end
    end
  end

  describe "the test of a provider" do
    test "sends one small request with the saved key, and keeps the result", %{root: root} do
      provider = provider!(root)
      ScriptedModel.script([{:text, "pong"}])

      assert {:ok, tested} = Ruby.test_provider(provider, actor: root)
      assert tested.test_result == :ok
      assert %DateTime{} = tested.tested_at

      assert [%{model: "anthropic:claude-opus-5-5", messages: messages, opts: opts}] =
               ScriptedModel.requests()

      assert opts[:api_key] == key()
      assert opts[:max_tokens] == 64
      refute Keyword.has_key?(opts, :tools)
      assert [%{role: :user, content: [%{text: "ping"}]}] = messages
    end

    test "keeps the reason of a failure, and nothing of the error", %{root: root} do
      provider = provider!(root)

      for {error, reason} <- [
            {%{status: 401, reason: "invalid x-api-key"}, :key_refused},
            {%{status: 429}, :provider_busy},
            {%{status: 503}, :provider_down},
            {%{status: 404}, :request_refused},
            {%{status: 400, reason: "You have reached your specified API usage limits"},
             :provider_limit},
            {:timeout, :provider_down},
            {:something_else, :unknown}
          ] do
        ScriptedModel.script([{:error, error}])
        assert {:ok, %{test_result: ^reason}} = Ruby.test_provider(provider, actor: root)
      end
    end

    test "sends nothing for a provider that has lost its key", %{root: root} do
      provider = provider!(root)
      # AshCloak keeps Base64 in the column. This is no value of the vault.
      Repo.query!("update ruby_providers set encrypted_api_key = $1", [
        Base.encode64("not a value")
      ])

      ScriptedModel.script([{:text, "pong"}])

      assert {:ok, %{test_result: :key_refused}} = Ruby.test_provider(provider, actor: root)
      assert ScriptedModel.requests() == []
    end

    test "sends nothing for a provider whose saved values no longer fit", %{root: root} do
      provider = provider!(root)
      # A key of a hosted service never goes over plain HTTP. No action
      # saves such an address, so the row gets it behind the actions.
      Repo.query!("update ruby_providers set base_url = 'http://gateway.example.org'")
      provider = Ruby.provider!(provider.id, actor: root)
      ScriptedModel.script([{:text, "pong"}])

      assert {:ok, %{test_result: :unknown}} = Ruby.test_provider(provider, actor: root)
      assert ScriptedModel.requests() == []
    end

    test "a change of the model forgets the last test, and a new name keeps it", %{root: root} do
      provider = provider!(root)
      ScriptedModel.script([{:text, "pong"}])
      assert {:ok, %{test_result: :ok} = tested} = Ruby.test_provider(provider, actor: root)

      assert {:ok, named} = Ruby.change_provider(tested, %{name: "Another name"}, actor: root)
      assert named.test_result == :ok
      assert named.tested_at == tested.tested_at

      assert {:ok, same} =
               Ruby.change_provider(named, %{model: named.model, offered: true}, actor: root)

      assert same.test_result == :ok

      assert {:ok, changed} =
               Ruby.change_provider(same, %{model: "claude-sonnet-5-5"}, actor: root)

      assert changed.test_result == nil
      assert changed.tested_at == nil
    end

    test "is for a root user alone, and nobody else spends anything", %{root: root} do
      provider = provider!(root)
      ScriptedModel.script([{:text, "pong"}])

      for actor <- [nil, user!()] do
        assert {:error, :forbidden} = Ruby.test_provider(provider, actor: actor)
      end

      assert ScriptedModel.requests() == []
      assert [%{tested_at: nil}] = Ruby.providers!(actor: root)
    end
  end
end
