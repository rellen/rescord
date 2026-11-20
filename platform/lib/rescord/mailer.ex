defmodule Rescord.Mailer do
  @moduledoc """
  The mailer of Rescord: the sign-in links and the invitations.

  A server sends through the SMTP server that its operator names (ADR
  0044), with the adapter `Swoosh.Adapters.SMTP` and `gen_smtp`: Postmark,
  Amazon SES, Mailgun, a mail host of the refuge, or a relay on the same
  machine. `smtp_options/1` turns the settings of `config/runtime.exs` into
  the options of the adapter.
  """

  use Swoosh.Mailer, otp_app: :rescord

  @typedoc """
  The SMTP settings of a server: the host and the port, the user and the
  password when the server asks for them, and how the connection is
  encrypted:

    * `:starttls` - a plain connection that STARTTLS encrypts, usually on
      port 587. It refuses a server that offers no STARTTLS.
    * `:tls` - a connection that is encrypted from the start, usually on
      port 465.
    * `:none` - no encryption, for a relay on the same machine or the same
      private network alone.
  """
  @type smtp :: %{
          host: String.t(),
          port: pos_integer,
          username: String.t() | nil,
          password: String.t() | nil,
          tls: :starttls | :tls | :none
        }

  @doc """
  The options of `Swoosh.Adapters.SMTP` for the settings `smtp`. With TLS,
  the client checks the certificate of the server against the certificates
  of the system, and checks the name of the host.
  """
  @spec smtp_options(smtp) :: keyword
  def smtp_options(%{host: host, port: port, tls: tls} = smtp) do
    verify = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      depth: 99,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    encryption =
      case tls do
        :starttls -> [ssl: false, tls: :always, tls_options: verify]
        :tls -> [ssl: true, tls: :never, sockopts: verify]
        :none -> [ssl: false, tls: :never]
      end

    auth =
      case smtp[:username] do
        nil -> [auth: :never]
        username -> [auth: :always, username: username, password: smtp[:password]]
      end

    [adapter: Swoosh.Adapters.SMTP, relay: host, port: port, retries: 2, no_mx_lookups: true] ++
      encryption ++ auth
  end
end
