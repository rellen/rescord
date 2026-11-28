import Config

# Jobs are not run unless a test runs them itself.
config :rescord, Oban, testing: :manual

# The usage counts stay in memory until a test writes them (ADR 0098).
config :rescord, Rescord.Usage.Counter, auto?: false
# A send of the usage counts goes to a stub of `Req.Test`.
config :rescord, Rescord.Usage.Sender, req_options: [plug: {Req.Test, Rescord.Usage.Sender}]
# A message of a channel of the notifications goes to a stub too (ADR 0106).
config :rescord, Rescord.Notifications.Channel,
  req_options: [plug: {Req.Test, Rescord.Notifications.Channel}]

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "RCqjVbP5zdhSYiU+ArBvz7f6Vj0YEk2VjYm0j+PfFkI",
  disable_async?: true

# An action in a transaction that Ash did not start loses its notification,
# and a page then hears nothing (ADR 0096). A test fails for it.
config :ash, :missed_notifications, :raise

# A page reads again at once after a change, with no wait, so a test writes
# and then renders (ADR 0096).
config :rescord, RescordWeb.LiveChanges, wait: 0

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
  # A browser test needs a real server (ADR 0023). A run of muex starts
  # several `mix test` at one time and has no browser test, so it starts no
  # server (ADR 0104, `RESCORD_MUTATION_RUN` in `mix.exs`).
  server: System.get_env("RESCORD_MUTATION_RUN") != "1"

# The catalogue of the components, at /dev/components: a browser test holds
# each example to the rules of a page (ADR 0095).
config :rescord, catalogue: true

# In test we don't send emails
config :rescord, Rescord.Mailer, adapter: Swoosh.Adapters.Test

# The tests keep the files of the attachments in a directory. A test that
# keeps a file gives it a temporary directory of its own (ADR 0038).
config :rescord, :storage, Rescord.Storage.Disk

# The secret that guards the private keys of the refuges (ADR 0043).
config :rescord, Rescord.Transfers.Keys, secret: "the secret of the test keys, 32 bytes or more"

# The same secret gives the key of the vault of the settings (ADR 0068).
config :rescord, Rescord.Vault, secret: "the secret of the test keys, 32 bytes or more"
config :rescord, Rescord.Storage.Disk, root: Path.join(System.tmp_dir!(), "rescord-test-store")

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
      browser_launch_timeout: 30_000,
      # The browsers start in this pool. phoenix_test_playwright 0.19.0 gives
      # the pool the global settings above only when the configuration names
      # the pool: with its default pool, the launch has the 4 seconds.
      browser_pools: [[id: :default_pool]]
    ] ++ chromium

# A request of the assistant goes to a scripted model (ADR 0069). This is a
# seam for the tests and no setting: no test reaches a provider.
config :rescord, :ruby_llm, Rescord.Ruby.ScriptedModel

# The job of a transfer writes its count after each file, so a test sees
# where a copy stopped (ADR 0100).
config :rescord, Rescord.Transfers.Actions.CopyFiles, progress_every: 0
