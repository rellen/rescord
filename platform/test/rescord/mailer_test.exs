defmodule Rescord.MailerTest do
  @moduledoc """
  Holds the SMTP options of the mailer (ADR 0044): how each mode encrypts
  the connection, that TLS checks the certificate and the name of the
  server, and that a user and a password go only to a server that asks.
  """

  use ExUnit.Case, async: true

  alias Rescord.Mailer

  @smtp %{host: "smtp.example.org", port: 587, username: nil, password: nil, tls: :starttls}

  test "STARTTLS is required, and checks the certificate and the name of the server" do
    options = Mailer.smtp_options(@smtp)

    assert options[:adapter] == Swoosh.Adapters.SMTP
    assert options[:relay] == "smtp.example.org"
    assert options[:tls] == :always
    assert options[:ssl] == false
    assert options[:tls_options][:verify] == :verify_peer
    assert options[:tls_options][:server_name_indication] == ~c"smtp.example.org"
    assert is_list(options[:tls_options][:cacerts])
    assert options[:auth] == :never
    refute Keyword.has_key?(options, :password)
  end

  test "TLS from the start checks the certificate on the socket" do
    options = Mailer.smtp_options(%{@smtp | tls: :tls, port: 465})

    assert options[:ssl] == true
    assert options[:tls] == :never
    assert options[:sockopts][:verify] == :verify_peer
  end

  test "no encryption is a choice of its own, for a relay on the same machine" do
    options = Mailer.smtp_options(%{@smtp | tls: :none, port: 25})

    assert options[:ssl] == false
    assert options[:tls] == :never
    refute Keyword.has_key?(options, :tls_options)
  end

  test "a user and a password go to a server that asks for them" do
    options = Mailer.smtp_options(%{@smtp | username: "apikey", password: "secret"})

    assert options[:auth] == :always
    assert options[:username] == "apikey"
    assert options[:password] == "secret"
  end
end
