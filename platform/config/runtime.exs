import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/rescord start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# Each value of the environment is read with `Shoddy.Env`, which raises an
# error that names the variable when its value is not correct.
if Shoddy.Env.boolean("PHX_SERVER", default: false, digits: true) do
  config :rescord, RescordWeb.Endpoint, server: true
end

# Not in the tests: the server of the tests keeps the port of config/test.exs
# (ADR 0023). This file runs last, so without the condition the tests would
# take port 4000, which is the port of `mix phx.server`.
if config_env() != :test do
  config :rescord, RescordWeb.Endpoint,
    http: [port: Shoddy.Env.integer("PORT", default: 4000, min: 1, max: 65_535)]
end

if config_env() == :dev do
  # The Garage of devenv (ADR 0038): its endpoint, its bucket, and the fixed
  # key that `devenv.nix` imports. That key opens a store on this machine
  # alone, and is no secret.
  # The secret that guards the private keys of the refuges of this machine
  # (ADR 0043). It is no secret on a machine for development.
  config :rescord, Rescord.Transfers.Keys, secret: "the secret of the development keys, 32 bytes"

  config :rescord, Rescord.Storage.S3,
    endpoint: Shoddy.Env.string("GARAGE_S3_ENDPOINT", default: "http://127.0.0.1:3900"),
    region: "garage",
    bucket: "rescord",
    access_key_id: "GK0000000000000000000000ad",
    secret_access_key: "000000000000000000000000000000000000000000000000000000000000dec0"
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :rescord, RescordWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/rescord_web/router\.ex$"E,
        ~r"lib/rescord_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # A required text: `Shoddy.Env.string/2` refuses a variable that is absent
  # or blank. For example: ecto://USER:PASS@HOST/DATABASE
  database_url = Shoddy.Env.string("DATABASE_URL")

  maybe_ipv6 =
    if Shoddy.Env.boolean("ECTO_IPV6", default: false, digits: true),
      do: [:inet6],
      else: []

  config :rescord, Rescord.Repo,
    # ssl: true,
    url: database_url,
    pool_size: Shoddy.Env.integer("POOL_SIZE", default: 10, min: 1),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  # Make each secret with `mix phx.gen.secret`, which gives 64 bytes.
  # The secret that guards the private keys of the refuges (ADR 0043). A
  # refuge keeps it with its backups: another secret cannot open the keys.
  config :rescord, Rescord.Transfers.Keys,
    secret: Shoddy.Env.string("RESCORD_KEY_SECRET", min_bytes: 32)

  # The photos that go through libvips at the same time (ADR 0056). Each can
  # take 150 MB to 300 MB while it works.
  config :rescord, Rescord.Images.Limit,
    slots: Shoddy.Env.integer("RESCORD_PHOTO_SLOTS", default: 2, min: 1, max: 64)

  # The store of the attachments (ADR 0038 and ADR 0044): a directory of
  # this machine, or a service that is compatible with S3. Each setting of
  # the chosen store is required, and there is no default service.
  storage =
    Shoddy.Env.one_of("RESCORD_STORAGE", [disk: Rescord.Storage.Disk, s3: Rescord.Storage.S3],
      default: Rescord.Storage.Disk
    )

  config :rescord, :storage, storage

  case storage do
    Rescord.Storage.Disk ->
      config :rescord, Rescord.Storage.Disk, root: Shoddy.Env.string("RESCORD_FILES_DIR")

    Rescord.Storage.S3 ->
      config :rescord, Rescord.Storage.S3,
        endpoint: Shoddy.Env.string("RESCORD_S3_ENDPOINT"),
        region: Shoddy.Env.string("RESCORD_S3_REGION", default: "auto"),
        bucket: Shoddy.Env.string("RESCORD_S3_BUCKET"),
        addressing: Shoddy.Env.one_of("RESCORD_S3_ADDRESSING", [:path, :virtual], default: :path),
        access_key_id: Shoddy.Env.string("RESCORD_S3_ACCESS_KEY_ID"),
        secret_access_key: Shoddy.Env.string("RESCORD_S3_SECRET_ACCESS_KEY")
  end

  # The mail: the sign-in links and the invitations go through the SMTP
  # server that the operator names (ADR 0044). The user and the password
  # are for a server that asks for them.
  config :rescord, :mail_from, {
    Shoddy.Env.string("RESCORD_MAIL_FROM_NAME", default: "Rescord"),
    Shoddy.Env.string("RESCORD_MAIL_FROM")
  }

  config :rescord,
         Rescord.Mailer,
         Rescord.Mailer.smtp_options(%{
           host: Shoddy.Env.string("RESCORD_SMTP_HOST"),
           port: Shoddy.Env.integer("RESCORD_SMTP_PORT", default: 587, min: 1, max: 65_535),
           username: Shoddy.Env.string("RESCORD_SMTP_USERNAME", default: nil),
           password: Shoddy.Env.string("RESCORD_SMTP_PASSWORD", default: nil),
           tls:
             Shoddy.Env.one_of("RESCORD_SMTP_TLS", [:starttls, :tls, :none], default: :starttls)
         })

  secret_key_base = Shoddy.Env.string("SECRET_KEY_BASE", min_bytes: 64)

  # The secret that signs a sign-in token.
  token_signing_secret = Shoddy.Env.string("TOKEN_SIGNING_SECRET", min_bytes: 64)

  config :rescord, token_signing_secret: token_signing_secret

  # The name of the host in each link that Rescord sends, such as
  # rescord.example.org. A reverse proxy in front of Rescord gives HTTPS.
  host = Shoddy.Env.string("PHX_HOST")

  # The address that the web server listens on (ADR 0044): 0.0.0.0, each
  # address of IPv4, by default, because a container often has no IPv6.
  # "127.0.0.1" for a reverse proxy on the same machine, and "::" for each
  # address of IPv6 and IPv4.
  listen_text = Shoddy.Env.string("RESCORD_LISTEN_ADDRESS", default: "0.0.0.0")

  listen_address =
    case :inet.parse_address(String.to_charlist(listen_text)) do
      {:ok, address} ->
        address

      {:error, _reason} ->
        raise ArgumentError,
              "the environment variable \"RESCORD_LISTEN_ADDRESS\" is not an IP address: #{inspect(listen_text)}"
    end

  # The reverse proxies that may say the address of a client (ADR 0046): a
  # proxy on the same machine by default.
  trusted_text = Shoddy.Env.string("RESCORD_TRUSTED_PROXIES", default: "127.0.0.0/8, ::1")

  case RescordWeb.ClientAddress.parse_networks(trusted_text) do
    {:ok, trusted} ->
      config :rescord, RescordWeb.ClientAddress, trusted: trusted

    {:error, entry} ->
      raise ArgumentError,
            "the environment variable \"RESCORD_TRUSTED_PROXIES\" holds #{inspect(entry)}, " <>
              "which is not an IP address or a network"
  end

  config :rescord, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :rescord, RescordWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: listen_address],
    secret_key_base: secret_key_base

  config :ash,
    keyset_signing_secret:
      :crypto.mac(
        :hmac,
        :sha256,
        secret_key_base,
        "ash keyset signing"
      )

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :rescord, RescordWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :rescord, RescordWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
