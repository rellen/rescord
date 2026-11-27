defmodule Rescord.ProductionConfigTest do
  @moduledoc """
  Reads `config/runtime.exs` as a release reads it in production (ADR
  0044), with the settings of `docs/self-hosting.md` in the environment:
  the mail goes through the SMTP server that the operator names, the store
  is the one that the operator chooses, and a missing required setting
  stops the start with its name.

  The tests change the environment of the operating system, so they do not
  run beside others.
  """

  use ExUnit.Case, async: false

  @required %{
    "DATABASE_URL" => "ecto://rescord:secret@db/rescord",
    "SECRET_KEY_BASE" => String.duplicate("s", 64),
    "TOKEN_SIGNING_SECRET" => String.duplicate("t", 64),
    "RESCORD_KEY_SECRET" => String.duplicate("k", 32),
    "PHX_HOST" => "rescord.example.org",
    "RESCORD_FILES_DIR" => "/var/lib/rescord/files",
    "RESCORD_SMTP_HOST" => "smtp.example.org",
    "RESCORD_MAIL_FROM" => "rescord@example.org"
  }

  @optional ~w(RESCORD_STORAGE RESCORD_S3_ENDPOINT RESCORD_S3_REGION RESCORD_S3_BUCKET
               RESCORD_S3_ADDRESSING
               RESCORD_S3_ACCESS_KEY_ID RESCORD_S3_SECRET_ACCESS_KEY RESCORD_SMTP_PORT
               RESCORD_SMTP_USERNAME RESCORD_SMTP_PASSWORD RESCORD_SMTP_TLS
               RESCORD_MAIL_FROM_NAME PHX_SERVER RESCORD_LISTEN_ADDRESS RESCORD_TRUSTED_PROXIES
               RESCORD_PHOTO_SLOTS)

  @s3 Map.merge(@required, %{
        "RESCORD_STORAGE" => "s3",
        "RESCORD_S3_ENDPOINT" => "https://t3.storage.dev",
        "RESCORD_S3_BUCKET" => "rescord",
        "RESCORD_S3_ACCESS_KEY_ID" => "key",
        "RESCORD_S3_SECRET_ACCESS_KEY" => "secret"
      })

  setup do
    names = Map.keys(@required) ++ @optional
    previous = Map.new(names, &{&1, System.get_env(&1)})
    Enum.each(names, &System.delete_env/1)

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    :ok
  end

  defp read(env) do
    System.put_env(env)
    Config.Reader.read!("config/runtime.exs", env: :prod)
  end

  test "with the required settings, the mail goes through SMTP and the files into a directory" do
    config = read(@required)

    assert config[:rescord][:storage] == Rescord.Storage.Disk
    assert config[:rescord][Rescord.Storage.Disk][:root] == "/var/lib/rescord/files"
    assert config[:rescord][:mail_from] == {"Rescord", "rescord@example.org"}

    mailer = config[:rescord][Rescord.Mailer]
    assert mailer[:adapter] == Swoosh.Adapters.SMTP
    assert mailer[:relay] == "smtp.example.org"
    assert mailer[:port] == 587
    assert mailer[:tls] == :always
    assert mailer[:auth] == :never

    assert config[:rescord][RescordWeb.Endpoint][:url][:host] == "rescord.example.org"
    assert config[:rescord][RescordWeb.Endpoint][:http][:ip] == {0, 0, 0, 0}
  end

  test "an S3 store needs its endpoint, and has no default service" do
    assert_raise ArgumentError, ~r/RESCORD_S3_ENDPOINT.*not set/, fn ->
      read(Map.put(@required, "RESCORD_STORAGE", "s3"))
    end

    config =
      read(
        Map.merge(@required, %{
          "RESCORD_STORAGE" => "s3",
          "RESCORD_S3_ENDPOINT" => "https://s3.example.org",
          "RESCORD_S3_BUCKET" => "rescord",
          "RESCORD_S3_ACCESS_KEY_ID" => "key",
          "RESCORD_S3_SECRET_ACCESS_KEY" => "secret"
        })
      )

    assert config[:rescord][:storage] == Rescord.Storage.S3
    assert config[:rescord][Rescord.Storage.S3][:endpoint] == "https://s3.example.org"
    assert config[:rescord][Rescord.Storage.S3][:region] == "auto"
    assert config[:rescord][Rescord.Storage.S3][:addressing] == :path

    config = read(Map.put(@s3, "RESCORD_S3_ADDRESSING", "virtual"))
    assert config[:rescord][Rescord.Storage.S3][:addressing] == :virtual
  end

  test "a missing required setting stops the start, and names the setting" do
    for name <- Map.keys(@required) do
      System.delete_env(name)

      assert_raise ArgumentError, ~r/#{name}.*not set/, fn ->
        read(Map.delete(@required, name))
      end
    end
  end

  test "the web server listens on the address of the setting" do
    config = read(Map.put(@required, "RESCORD_LISTEN_ADDRESS", "127.0.0.1"))
    assert config[:rescord][RescordWeb.Endpoint][:http][:ip] == {127, 0, 0, 1}

    config = read(Map.put(@required, "RESCORD_LISTEN_ADDRESS", "::"))
    assert config[:rescord][RescordWeb.Endpoint][:http][:ip] == {0, 0, 0, 0, 0, 0, 0, 0}

    assert_raise ArgumentError, ~r/RESCORD_LISTEN_ADDRESS/, fn ->
      read(Map.put(@required, "RESCORD_LISTEN_ADDRESS", "localhost"))
    end
  end

  test "two photos go through libvips at once, unless the setting gives another number" do
    config = read(@required)
    assert config[:rescord][Rescord.Images.Limit][:slots] == 2

    config = read(Map.put(@required, "RESCORD_PHOTO_SLOTS", "6"))
    assert config[:rescord][Rescord.Images.Limit][:slots] == 6

    assert_raise ArgumentError, ~r/RESCORD_PHOTO_SLOTS/, fn ->
      read(Map.put(@required, "RESCORD_PHOTO_SLOTS", "0"))
    end
  end

  test "a proxy on the same machine is trusted, unless the setting names others" do
    config = read(@required)

    assert config[:rescord][RescordWeb.ClientAddress][:trusted] ==
             [{{127, 0, 0, 0}, 8}, {{0, 0, 0, 0, 0, 0, 0, 1}, 128}]

    config = read(Map.put(@required, "RESCORD_TRUSTED_PROXIES", "172.16.0.0/12, 10.0.0.1"))

    assert config[:rescord][RescordWeb.ClientAddress][:trusted] ==
             [{{172, 16, 0, 0}, 12}, {{10, 0, 0, 1}, 32}]

    assert_raise ArgumentError, ~r/RESCORD_TRUSTED_PROXIES.*"172\.16\.0\.0\/40"/, fn ->
      read(Map.put(@required, "RESCORD_TRUSTED_PROXIES", "127.0.0.1, 172.16.0.0/40"))
    end
  end

  test "a setting that is not allowed stops the start, and names what is" do
    assert_raise ArgumentError, ~r/RESCORD_SMTP_TLS.*"starttls", "tls", "none"/, fn ->
      read(Map.put(@required, "RESCORD_SMTP_TLS", "ssl"))
    end

    assert_raise ArgumentError, ~r/RESCORD_STORAGE/, fn ->
      read(Map.put(@required, "RESCORD_STORAGE", "tigris"))
    end

    assert_raise ArgumentError, ~r/RESCORD_S3_ADDRESSING.*"path", "virtual"/, fn ->
      read(Map.put(@s3, "RESCORD_S3_ADDRESSING", "vhost"))
    end
  end

  test "a user and a password go to the SMTP server, over TLS from the start" do
    config =
      read(
        Map.merge(@required, %{
          "RESCORD_SMTP_USERNAME" => "apikey",
          "RESCORD_SMTP_PASSWORD" => "secret",
          "RESCORD_SMTP_TLS" => "tls",
          "RESCORD_SMTP_PORT" => "465",
          "RESCORD_MAIL_FROM_NAME" => "Wattle Creek"
        })
      )

    mailer = config[:rescord][Rescord.Mailer]
    assert mailer[:auth] == :always
    assert mailer[:username] == "apikey"
    assert mailer[:ssl] == true
    assert mailer[:port] == 465
    assert config[:rescord][:mail_from] == {"Wattle Creek", "rescord@example.org"}
  end
end
