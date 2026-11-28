defmodule RescordWeb.RubyPagesTest do
  @moduledoc """
  Holds the pages of the providers of the assistant, for a root user
  (ADR 0069): who opens them, the fields of each service, a refusal beside
  its field, the test of a provider, and that no page and no log holds a
  key (ADR 0068).

  One test changes the level of the log, so the tests do not run beside
  others.
  """

  use RescordWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Rescord.AccountsFixtures
  import Rescord.RubyFixtures

  alias Rescord.Ruby
  alias Rescord.Ruby.{LLM, ScriptedModel}

  @secret "sk-test-a-key-that-no-page-shows"

  setup context do
    root = root!()
    {:ok, root: root, conn: sign_in(context.conn, root)}
  end

  defp open(conn, path) do
    {:ok, view, _html} = live(conn, path)
    {view, render_async(view)}
  end

  defp save(view, conn, fields) do
    {:ok, view, _html} =
      view |> form("#provider", provider: fields) |> render_submit() |> follow_redirect(conn)

    {view, render_async(view)}
  end

  describe "who opens the pages" do
    test "only a root user", %{conn: conn, root: root} do
      provider = provider!(root)
      paths = [~p"/root/ruby", ~p"/root/ruby/new", ~p"/root/ruby/#{provider.id}"]

      for path <- paths do
        assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), path)

        assert {:error, {:redirect, %{to: "/"}}} =
                 build_conn() |> sign_in(user!()) |> live(path)

        assert {:ok, _view, _html} = live(conn, path)
      end
    end

    test "a path with no provider goes back to the list", %{conn: conn} do
      for id <- [Ecto.UUID.generate(), "not-an-id"] do
        assert {:error, {:live_redirect, %{to: "/root/ruby"}}} = live(conn, ~p"/root/ruby/#{id}")
      end
    end
  end

  describe "the list" do
    test "of a new server gives the steps, and the root page says so", %{conn: conn} do
      {view, html} = open(conn, ~p"/root/ruby")

      assert html =~ "This server has no provider yet, so no organisation sees Ruby."
      assert has_element?(view, ~s(a[href="/root/ruby/new"]), "Add a provider")
      refute has_element?(view, "#providers")

      {view, _html} = open(conn, ~p"/root")
      assert view |> element("#ruby-line") |> render() =~ "no provider yet"
      assert has_element?(view, ~s(#ruby-line a[href="/root/ruby"]))
    end

    test "has a row for each provider, with no key", %{conn: conn, root: root} do
      provider = provider!(root, %{api_key: @secret})
      provider!(root, %{name: "The shed server", kind: :ollama, model: "a-model", api_key: nil})

      {view, html} = open(conn, ~p"/root/ruby")

      row = view |> element("#provider-#{provider.id}") |> render()
      assert row =~ "claude-opus-5-5"
      assert row =~ "Ends in hows, set on #{RescordWeb.RubyWords.day(provider.key_set_at)}"
      assert row =~ "Not tested"
      assert has_element?(view, ~s(#provider-#{provider.id} td[data-label="Offered"]), "No")
      assert has_element?(view, ~s(#provider-#{provider.id} a[href="/root/ruby/#{provider.id}"]))
      assert html =~ "Takes no key"
      refute html =~ @secret

      {view, _html} = open(conn, ~p"/root")
      assert view |> element("#ruby-line") |> render() =~ "2 providers, 0 offered"
    end
  end

  describe "a new provider" do
    test "has the fields of its service", %{conn: conn} do
      {view, _html} = open(conn, ~p"/root/ruby/new")
      assert has_element?(view, ~s(nav a[aria-current="true"]), "Anthropic")
      assert has_element?(view, ~s(#provider_model[value="claude-opus-5-5"]))

      assert has_element?(
               view,
               ~s(#provider_api_key[type="password"][autocomplete="new-password"])
             )

      assert has_element?(view, "#provider_effort")
      refute has_element?(view, "#provider_base_url")
      refute has_element?(view, "#provider_region")
      refute has_element?(view, "#provider_offered")
      assert has_element?(view, "blockquote", "Anthropic, in the United States")

      {view, _html} = open(conn, ~p"/root/ruby/new?kind=bedrock")
      assert has_element?(view, "#provider_region")
      refute has_element?(view, "#provider_base_url")

      {view, _html} = open(conn, ~p"/root/ruby/new?kind=ollama")
      assert has_element?(view, ~s(nav a[aria-current="true"]), "Ollama")
      assert has_element?(view, ~s(#provider_base_url[value="http://localhost:11434/v1"]))
      assert has_element?(view, ~s(#provider_context_tokens[value="32000"]))
      refute has_element?(view, "#provider_api_key")
      refute has_element?(view, "#provider_effort")
      assert has_element?(view, "blockquote", "this server")

      {view, _html} = open(conn, ~p"/root/ruby/new?kind=openai_compatible")
      assert has_element?(view, "#provider_base_url")
      assert has_element?(view, "#provider_api_key")
      assert has_element?(view, "#provider_price_input")

      # A kind that Rescord does not have is the first one.
      {view, _html} = open(conn, ~p"/root/ruby/new?kind=another")
      assert has_element?(view, ~s(nav a[aria-current="true"]), "Anthropic")
    end

    test "a link changes the service, with no reload", %{conn: conn} do
      {view, _html} = open(conn, ~p"/root/ruby/new")

      view |> element("nav a", "Ollama") |> render_click()

      assert_patch(view, ~p"/root/ruby/new?kind=ollama")
      refute has_element?(view, "#provider_api_key")
    end

    test "is added with its key, and no page shows the key", %{conn: conn, root: root} do
      {view, _html} = open(conn, ~p"/root/ruby/new")

      {view, html} = save(view, conn, %{name: "Anthropic", api_key: @secret})

      assert [provider] = Ruby.providers!(actor: root)
      assert html =~ "Anthropic is added."
      assert html =~ "The key ends in hows and was set on"
      assert has_element?(view, ~s(#provider_api_key[value=""]))
      refute html =~ @secret

      assert provider.kind == :anthropic
      assert provider.default_allowance == 2_000
      assert {:ok, %{api_key: @secret}} = LLM.profile_of(provider)
    end

    test "a refusal is beside its field, and the key does not come back", %{
      conn: conn,
      root: root
    } do
      {view, _html} = open(conn, ~p"/root/ruby/new?kind=openai_compatible")

      html =
        view
        |> form("#provider",
          provider: %{
            name: "The gateway of the network",
            base_url: "http://llm.example.org/v1",
            model: "a-model",
            api_key: @secret
          }
        )
        |> render_submit()

      assert has_element?(view, ~s(#provider_base_url[aria-invalid="true"]))

      assert has_element?(
               view,
               "#provider_base_url-error",
               "a key goes only to an address that starts with https://"
             )

      # What the person typed stays, but the key.
      assert has_element?(view, ~s(#provider_name[value="The gateway of the network"]))
      assert has_element?(view, ~s(#provider_api_key[value=""]))
      assert has_element?(view, "#provider_api_key-hint", "Type it again")
      assert has_element?(view, "blockquote", "the model at the address llm.example.org")
      refute html =~ @secret
      assert Ruby.providers!(actor: root) == []
    end

    test "a hosted service needs a key, and an amount is an amount", %{conn: conn} do
      {view, _html} = open(conn, ~p"/root/ruby/new")

      view |> form("#provider", provider: %{name: "Anthropic"}) |> render_submit()
      assert has_element?(view, "#provider_api_key-error", "this service needs a key")

      view
      |> form("#provider", provider: %{name: "", api_key: @secret, default_allowance: "a lot"})
      |> render_submit()

      assert has_element?(
               view,
               "#provider_default_allowance-error",
               "give an amount in US dollars"
             )

      # The part with the limits is open, so that the words are in view.
      assert has_element?(view, "details#provider-limits[open]")

      view
      |> form("#provider",
        provider: %{
          name: "",
          api_key: @secret,
          max_output_tokens: "100",
          default_allowance: "12.50"
        }
      )
      |> render_submit()

      assert has_element?(view, "#provider_name-error", "give the provider a name")
      assert has_element?(view, "#provider_max_output_tokens-error", "from 256 to 32,000")
    end
  end

  describe "one provider" do
    setup %{root: root} do
      %{provider: provider!(root, %{api_key: @secret})}
    end

    test "shows its fields, the place of its records, and no key",
         %{conn: conn, provider: provider} do
      {view, html} = open(conn, ~p"/root/ruby/#{provider.id}")

      assert has_element?(view, "h1", "Anthropic")
      assert has_element?(view, ~s(#provider_model[value="claude-opus-5-5"]))
      assert has_element?(view, ~s(#provider_default_allowance[value="20"]))
      assert has_element?(view, ~s(#provider_api_key[value=""]))
      assert has_element?(view, "#provider_offered:not([checked])")
      assert has_element?(view, "blockquote", "Records go to Anthropic, in the United States")
      assert html =~ "Nobody tested this provider with its key yet."
      assert html =~ "Rescord knows the prices of this model."
      refute has_element?(view, "#provider_price_input")
      refute html =~ @secret
    end

    test "a change with an empty key field keeps the key",
         %{conn: conn, root: root, provider: provider} do
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")

      {view, html} =
        save(view, conn, %{
          name: "Sonnet, for a trial",
          model: "claude-sonnet-5-5",
          offered: "true",
          default_allowance: "12.50"
        })

      assert html =~ "Sonnet, for a trial is saved."
      assert has_element?(view, "#provider_offered[checked]")

      assert [changed] = Ruby.providers!(actor: root)
      assert changed.model == "claude-sonnet-5-5"
      assert changed.offered
      assert changed.default_allowance == 1_250
      assert changed.key_set_at == provider.key_set_at
      assert {:ok, %{api_key: @secret}} = LLM.profile_of(changed)
    end

    test "a key that is typed takes the place of the old one",
         %{conn: conn, root: root, provider: provider} do
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")

      {_view, html} = save(view, conn, %{api_key: "sk-test-the-next-key-9z9z"})

      assert html =~ "The key ends in 9z9z"
      refute html =~ "sk-test-the-next-key-9z9z"
      assert [changed] = Ruby.providers!(actor: root)
      assert {:ok, %{api_key: "sk-test-the-next-key-9z9z"}} = LLM.profile_of(changed)
    end

    test "a refused field saves nothing, also not the key that came with it",
         %{conn: conn, root: root, provider: provider} do
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")

      html =
        view
        |> form("#provider", provider: %{model: "", api_key: "sk-test-the-next-key-9z9z"})
        |> render_submit()

      assert has_element?(view, "#provider_model-error", "name the model")
      assert has_element?(view, "#provider_api_key-hint", "Type it again")
      refute html =~ "sk-test-the-next-key-9z9z"

      assert [same] = Ruby.providers!(actor: root)
      assert same.key_set_at == provider.key_set_at
      assert {:ok, %{api_key: @secret}} = LLM.profile_of(same)
    end

    test "the test says that the provider answered", %{conn: conn, provider: provider} do
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")
      ScriptedModel.script([{:text, "pong"}])

      view |> element("#test") |> render_click()
      # The first use of the model catalogue takes some seconds.
      html = render_async(view, 20_000)

      assert has_element?(view, ~s(#test-result[role="status"]), "The provider answered, on")
      refute has_element?(view, "#test[disabled]")
      refute html =~ @secret
      assert [%{opts: opts}] = ScriptedModel.requests()
      assert opts[:api_key] == @secret
    end

    test "the test says why it failed, and what to do", %{conn: conn, provider: provider} do
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")
      ScriptedModel.script([{:error, %{status: 401, reason: "invalid x-api-key"}}])

      view |> element("#test") |> render_click()
      # The first use of the model catalogue takes some seconds.
      html = render_async(view, 20_000)

      assert has_element?(view, ~s(#test-result[role="alert"]), "the service refused the key")
      refute html =~ "invalid x-api-key"

      # The list says it too.
      {view, _html} = open(conn, ~p"/root/ruby")
      assert has_element?(view, ~s(#provider-#{provider.id} [data-state="alert"]), "Failed")
    end

    test "is removed, and the root page counts it no more",
         %{conn: conn, root: root, provider: provider} do
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")

      {:ok, view, html} = view |> element("#remove") |> render_click() |> follow_redirect(conn)

      assert html =~ "Anthropic is removed, and Rescord deleted its key."
      assert render_async(view) =~ "This server has no provider yet"
      assert Ruby.providers!(actor: root) == []
    end
  end

  describe "the log" do
    setup do
      level = Logger.level()
      on_exit(fn -> Logger.configure(level: level) end)
    end

    test "of a form with a key holds no key", %{conn: conn, root: root} do
      provider = provider!(root)
      {view, _html} = open(conn, ~p"/root/ruby/#{provider.id}")

      log =
        capture_log(fn ->
          Logger.configure(level: :debug)
          save(view, conn, %{api_key: @secret})
          Logger.configure(level: :warning)
        end)

      # The log did hold the event of the form, so the test looked at something.
      assert log =~ ~s(HANDLE EVENT "save")
      assert log =~ "[FILTERED]"
      refute log =~ @secret
    end
  end
end
