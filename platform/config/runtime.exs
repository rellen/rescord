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
  # The store of the attachments: Tigris, or another service that is
  # compatible with S3 (ADR 0038).
  config :rescord, Rescord.Storage.S3,
    endpoint: Shoddy.Env.string("RESCORD_S3_ENDPOINT", default: "https://t3.storage.dev"),
    region: Shoddy.Env.string("RESCORD_S3_REGION", default: "auto"),
    bucket: Shoddy.Env.string("RESCORD_S3_BUCKET"),
    access_key_id: Shoddy.Env.string("RESCORD_S3_ACCESS_KEY_ID"),
    secret_access_key: Shoddy.Env.string("RESCORD_S3_SECRET_ACCESS_KEY")

  secret_key_base = Shoddy.Env.string("SECRET_KEY_BASE", min_bytes: 64)

  # The secret that signs a sign-in token.
  token_signing_secret = Shoddy.Env.string("TOKEN_SIGNING_SECRET", min_bytes: 64)

  config :rescord, token_signing_secret: token_signing_secret

  host = System.get_env("PHX_HOST") || "example.com"

  config :rescord, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :rescord, RescordWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
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

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :rescord, Rescord.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
