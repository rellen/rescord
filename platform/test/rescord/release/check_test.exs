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
    previous = Application.get_env(:rescord, Rescord.Mailer)
    Application.put_env(:rescord, Rescord.Mailer, Rescord.Mailer.smtp_options(settings))
    on_exit(fn -> Application.put_env(:rescord, Rescord.Mailer, previous) end)
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

  test "the report names each check, and passes only with no fault" do
    report = Check.format([{:ok, "database", "PostgreSQL 18.1"}, {:fail, "store", "no"}])
    assert report =~ "ok    database   PostgreSQL 18.1"
    assert report =~ "FAIL  store      no"

    refute Check.passed?([{:ok, "a", ""}, {:fail, "b", ""}])
    assert Check.passed?([{:ok, "a", ""}, {:note, "b", ""}])
  end
end
