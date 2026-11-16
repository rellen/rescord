import Config

# Jobs are not run unless a test runs them itself.
config :rescord, Oban, testing: :manual

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "RCqjVbP5zdhSYiU+ArBvz7f6Vj0YEk2VjYm0j+PfFkI",
  disable_async?: true

# The secret that signs a sign-in token, for the tests only.
config :rescord,
  token_signing_secret: "VDTYZSc078CDlK1BowcxqaEqUjVYsKD9V8fnz9wwyYrAsRYDWwZLvr8fATXrUJCM"

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :rescord, Rescord.Repo,
  username: "postgres",
  password: "postgres",
  # devenv sets PGHOST and PGPORT; it can move Postgres off 5432 when that port is taken.
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  database: "rescord_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# The tests run a server on port 4002, for the browser tests. Two runs of
# `mix test` at one time cannot both have that port.
config :rescord, RescordWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9iDnT6galUTuMetbw7HGDpETn9kOplPWofCu2/hsMdMN7kGHzrwJ4iTte0GffAyG",
  # A browser test needs a real server (ADR 0023).
  server: true

# In test we don't send emails
config :rescord, Rescord.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# The browser tests (ADR 0023). A request of the browser, and a LiveView that
# it opens, use the database transaction of the test.
config :rescord, :sql_sandbox, true

# The driver of Playwright is in <assets dir>/node_modules/playwright. devenv
# sets PLAYWRIGHT_ASSETS_DIR to the driver of nixpkgs. PLAYWRIGHT_CHROMIUM
# names a Chromium for a machine whose browser is not the one of the driver.
chromium =
  case System.get_env("PLAYWRIGHT_CHROMIUM") do
    nil -> []
    path -> [executable_path: path]
  end

config :phoenix_test,
  otp_app: :rescord,
  endpoint: RescordWeb.Endpoint,
  playwright:
    [
      assets_dir: System.get_env("PLAYWRIGHT_ASSETS_DIR", "assets"),
      browser: :chromium,
      # The default is 4 seconds. A cold or busy machine needs more, and a
      # launch that is too slow makes each browser test invalid.
      browser_launch_timeout: 30_000
    ] ++ chromium
