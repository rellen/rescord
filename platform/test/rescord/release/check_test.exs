defmodule Rescord.Release.CheckTest do
  @moduledoc """
  Holds the checks of `bin/check` (ADR 0049): each one passes on a server
  that is ready, and names the fault on one that is not. The SMTP checks
  talk to a real SMTP server, the example server of `gen_smtp`, which takes
  the user `username` with the password `PaSSw0rd`.

  The tests change the configuration of the mailer and of the store, so
  they do not run beside others.
  """

  use Rescord.DataCase, async: false

  import Swoosh.TestAssertions

  alias Rescord.Release.Check

  defp smtp_server! do
    name = :"check_smtp_#{System.unique_integer([:positive])}"

    {:ok, _} = Application.ensure_all_started(:gen_smtp)

    {:ok, _} =
      :gen_smtp_server.start(name, :smtp_server_example,
        port: 0,
        domain: "localhost",
        sessionoptions: [callbackoptions: [auth: true]]
      )

    on_exit(fn -> :gen_smtp_server.stop(name) end)
    :ranch.get_port(name)
  end

  defp mailer!(settings) do
    Shoddy.Tests.put_app_env(:rescord, Rescord.Mailer, Rescord.Mailer.smtp_options(settings))
  end

  defp settings(port, username, password),
    do: %{host: "127.0.0.1", port: port, username: username, password: password, tls: :none}

  describe "the database" do
    test "answers, and is PostgreSQL 18 or later" do
      assert {:ok, "database", "PostgreSQL 18" <> _} = Check.database()
    end
  end

  describe "the migrations" do
    test "have each run in the database of the tests" do
      assert {:ok, "migrations", "each migration has run"} = Check.migrations()
    end
  end

  describe "the store" do
    @describetag :tmp_dir

    test "takes, gives back and deletes a file, and leaves nothing", %{tmp_dir: tmp_dir} do
      Rescord.StorageFixtures.disk_store!(tmp_dir)

      assert {:ok, "store", words} = Check.store()
      assert words =~ "the directory #{tmp_dir}"
      assert File.ls!(tmp_dir) == []
    end

    test "names the fault when the directory cannot take a file", %{tmp_dir: tmp_dir} do
      # A file where the directory of the files must be.
      root = Path.join(tmp_dir, "not-a-directory")
      File.write!(root, "")
      Rescord.StorageFixtures.disk_store!(root)

      assert {:fail, "store", words} = Check.store()
      assert words =~ "the put of a file gave"
    end
  end

  describe "the SMTP server" do
    test "takes the user and the password, and sends nothing" do
      mailer!(settings(smtp_server!(), "username", "PaSSw0rd"))

      assert {:ok, "mail", words} = Check.smtp()
      assert words =~ "takes the connection, with no TLS, and the user username"
      refute words =~ "PaSSw0rd"
    end

    test "says that it refused the password, and does not print it" do
      mailer!(settings(smtp_server!(), "username", "wrong-secret"))

      assert {:fail, "mail", words} = Check.smtp()
      assert words =~ "the server refused the user and the password"
      refute words =~ "wrong-secret"
    end

    test "says that there is no connection" do
      # A port that nothing listens on any more.
      {:ok, socket} = :gen_tcp.listen(0, [])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)
      mailer!(settings(port, nil, nil))

      assert {:fail, "mail", words} = Check.smtp()
      assert words =~ "no connection"
    end

    test "says that another adapter sends the mail" do
      assert {:note, "mail", words} = Check.smtp()
      assert words =~ "Swoosh.Adapters.Test"
    end
  end

  describe "the test email" do
    test "goes to the address through the mailer" do
      assert {:ok, "email", words} = Check.test_email("someone@example.org")
      assert words =~ "sent to someone@example.org"
      assert_email_sent(subject: "Rescord can send mail", to: "someone@example.org")
    end
  end

  describe "the vault" do
    import Rescord.AccountsFixtures
    import Rescord.RubyFixtures

    @old "the secret that the server had before, 32 bytes"
    @new "the secret that the server has now, 32 bytes long"

    test "has nothing on a new server" do
      assert {:ok, "vault", "no encrypted value yet"} = Check.vault()
    end

    test "counts the secrets of the settings and the keys of the transfers" do
      root = root!()
      provider!(root)
      assert {:ok, "vault", "the one encrypted value opens with the secret" <> _} = Check.vault()

      Rescord.Transfers.Keys.of(organisation!(root))

      assert {:ok, "vault", "each of the 2 encrypted values opens with the secret of this server"} =
               Check.vault()
    end

    test "says what to do while the secret of the server changes" do
      secrets!(@old)
      root = root!()
      provider!(root)
      Rescord.Transfers.Keys.of(organisation!(root))
      secrets!(@new, @old)
      provider!(root, %{name: "Another one"})

      assert {:note, "vault", words} = Check.vault()

      assert words ==
               "2 of 3 encrypted values open with the previous secret alone: run bin/rotate-vault"

      Rescord.Vault.rotate()
      Rescord.Transfers.rewrap_keys()

      assert {:note, "vault", words} = Check.vault()

      assert words ==
               "each of the 3 encrypted values opens with the secret of today: " <>
                 "take RESCORD_KEY_SECRET_PREVIOUS out"
    end

    test "fails for a value that no secret of the server opens, and names no secret" do
      secrets!(@old)
      provider!(root!())
      secrets!(@new)

      assert {:fail, "vault", words} = Check.vault()
      assert words =~ "1 of 1 encrypted values opens with no secret of this server"
      refute words =~ @old
      refute words =~ @new
    end
  end

  describe "the assistant" do
    import Rescord.AccountsFixtures
    import Rescord.RubyFixtures

    alias Rescord.Ruby
    alias Rescord.Ruby.ScriptedModel

    test "has no provider on a new server" do
      assert [{:note, "assistant", "no provider yet. A root user adds one at /root/ruby"}] =
               Check.assistant()
    end

    test "has a line for each provider, with its place, and no key" do
      root = root!()
      provider = provider!(root)

      place =
        "Anthropic: the model claude-opus-5-5, records go to Anthropic, in the United States and other countries"

      assert [{:note, "assistant", words}] = Check.assistant()
      assert words == place <> ". Not offered to an organisation"

      {:ok, provider} = Ruby.change_provider(provider, %{offered: true}, actor: root)
      assert [{:note, "assistant", words}] = Check.assistant()
      assert words == place <> ". Never tested: press Test at /root/ruby"

      ScriptedModel.script([{:text, "pong"}, {:error, %{status: 401}}])
      {:ok, provider} = Ruby.test_provider(provider, actor: root)
      day = Calendar.strftime(provider.tested_at, "%-d %B %Y")
      assert [{:ok, "assistant", words}] = Check.assistant()
      assert words == place <> ". The last test passed on #{day}"

      {:ok, _provider} = Ruby.test_provider(provider, actor: root)
      assert [{:fail, "assistant", words}] = Check.assistant()
      assert words == place <> ". The last test failed on #{day}: key_refused"

      shed = %{name: "The shed server", kind: :ollama, model: "a-model", api_key: nil}
      provider!(root, shed)
      assert [_anthropic, {:note, "assistant", words}] = Check.assistant()
      assert words =~ "The shed server: the model a-model, records go to this server"

      refute inspect(Check.assistant()) =~ key()
      # No line sent a request: the script had two steps, for the two tests.
      assert length(ScriptedModel.requests()) == 2
    end

    test "fails for a provider that an older rule saved, or that lost its key" do
      provider!(root!())
      Repo.query!("update ruby_providers set key_set_at = null, encrypted_api_key = null")

      assert [{:fail, "assistant", words}] = Check.assistant()
      assert words =~ "countries: this service needs a key"
    end
  end

  describe "the usage counts" do
    import Rescord.AccountsFixtures

    alias Rescord.Usage

    @endpoint "https://collector.example.org/v1/metrics"

    setup do
      :persistent_term.erase({Rescord.Usage, :mode})
      on_exit(fn -> :persistent_term.erase({Rescord.Usage, :mode}) end)
      %{root: root!()}
    end

    test "stay on a new server, which is no fault" do
      assert {:ok, "usage", "kept on this server, and sent nowhere"} = Check.usage()
    end

    test "are a note when they are off", %{root: root} do
      {:ok, _settings} = Usage.save_settings(%{mode: :off}, actor: root)
      assert {:note, "usage", _words} = Check.usage()
    end

    test "are a fault when the last send failed, and the line names no address", %{
      root: root
    } do
      {:ok, _settings} = Usage.save_settings(%{mode: :send, endpoint: @endpoint}, actor: root)
      assert {:ok, "usage", words} = Check.usage()
      refute words =~ "collector"

      today = Date.utc_today()
      Usage.add_count!(Date.add(today, -1), :tools, :page, "dose", 1, authorize?: false)
      Rescord.Repo.query!("update usage_settings set sending_since = $1", [Date.add(today, -1)])
      Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 500, ""))
      :ok = Usage.send_due(today)

      assert {:fail, "usage", words} = Check.usage()
      assert words == "sent each day, and the last send failed (status). See /root/usage"

      Req.Test.stub(Rescord.Usage.Sender, &Plug.Conn.send_resp(&1, 200, ""))
      :ok = Usage.send_due(today)
      assert {:ok, "usage", words} = Check.usage()
      assert words =~ "Each day up to #{Date.to_iso8601(Date.add(today, -1))} is done"
    end
  end

  test "the report names each check, and passes only with no fault" do
    report = Check.format([{:ok, "database", "PostgreSQL 18.1"}, {:fail, "store", "no"}])
    assert report =~ "ok    database   PostgreSQL 18.1"
    assert report =~ "FAIL  store      no"

    refute Check.passed?([{:ok, "a", ""}, {:fail, "b", ""}])
    assert Check.passed?([{:ok, "a", ""}, {:note, "b", ""}])
  end
end
