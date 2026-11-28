# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash_oban, pro?: false

# The library that reaches the provider of the assistant (ADR 0069). These
# are code and no settings: no operator sets them (ADR 0068).
config :req_llm,
  # A root user names the model of a provider. ReqLLM warns at each request
  # for a model that its catalogue does not have.
  warn_unverified_models: false,
  # ReqLLM reads a file `.env` of the working directory when Mix is there.
  # The key of a provider comes from its row, and from nowhere else.
  load_dotenv: false,
  # A request that fails holds the conversation in its struct. This keeps
  # it out of what `inspect/1` shows.
  redact_context: true

# The change that `emit` adds to an action does not say that it is temporal
# safe (Ash 3.38.1), so Ash refuses a signal of a temporal resource. The
# change only reads the record and runs the listeners through Ash, as of the
# instant of the action (ADR 0067). Ash reads this when it compiles. Take it
# out when Ash declares the change temporal safe.
# The amounts of the expenses are money (ADR 0082). Rescord converts no
# amount, so the service of ex_money that fetches exchange rates stays off.
config :ex_money, auto_start_exchange_rate_service: false

config :ash, :temporal_safe_modules, [Ash.Resource.Change.EmitSignal]

config :rescord, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10, workflow: 10],
  lifeline: [rescue_after: {2, :hours}],
  pruner: [max_age: {1, :day}],
  repo: Rescord.Repo,
  # The tasks of the routines, each hour (ADR 0033). A day starts at a
  # different hour in each time zone.
  cron: [crontab: [{"7 * * * *", Rescord.Tasks.Workers.GenerateTasks}]]

# These enable behaviors that will become the default in the next major
# version of Ash. Setting them now opts your application into the new
# behavior and ensures a seamless upgrade. See the backwards compatibility
# guide for an explanation of each setting:
# https://hexdocs.pm/ash/backwards-compatibility-config.html
config :ash,
  allow_forbidden_field_for_relationships_by_default: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  default_string_length_count: :codepoints,
  infer_generic_action_reactors?: false,
  many_to_many_destroy_destination_on_match?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec, AshMoney.Types.Money]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :pipelines,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    # `use Rescord.Resource` is a resource too (ADR 0013). The formatter needs
    # the extensions that it adds, and the same order of sections.
    "Rescord.Resource": [
      type: Ash.Resource,
      extensions: [AshPaperTrail.Resource, AshArchival.Resource],
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :pipelines,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

# The time zone rules, for the time zone of an organisation (ADR 0026).
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# The forms of a date, a time and a number in the locale of an organisation
# (ADR 0075). The files of these locales are in `priv/localize/locales`, and
# `mix localize.download_locales` fetches them again after an update of
# `localize`. `Rescord.Accounts.locales/0` is the list that a person chooses
# from: `en-US` there is `en` here. Rescord gives the locale with each call,
# so the default here is only for a call that forgets it: without it, the
# variable `LANG` of the server would decide.
config :localize,
  otp_app: :rescord,
  default_locale: :"en-AU",
  supported_locales: [
    :en,
    :"en-001",
    :"en-AU",
    :"en-CA",
    :"en-GB",
    :"en-IE",
    :"en-IN",
    :"en-NZ",
    :"en-ZA"
  ]

config :rescord,
  # `use Rescord.Resource` stands for `use Ash.Resource` (ADR 0013).
  base_resources: [Rescord.Resource],
  ecto_repos: [Rescord.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [
    Rescord.Accounts,
    Rescord.Lists,
    Rescord.Residents,
    Rescord.Locations,
    Rescord.Journal,
    Rescord.Photos,
    Rescord.Tasks,
    Rescord.Inventory,
    Rescord.Transfers,
    Rescord.Ruby,
    Rescord.Calendars,
    Rescord.Expenses,
    Rescord.Reports
  ],
  # The module of the web layer that words the reports (ADR 0076).
  report_wording: RescordWeb.ReportWords,
  # Each domain other than the accounts holds its own grants (ADR 0024).
  grant_sources: [
    Rescord.Lists.Grants,
    Rescord.Residents.Grants,
    Rescord.Locations.Grants,
    Rescord.Journal.Grants,
    Rescord.Photos.Grants,
    Rescord.Tasks.Grants,
    Rescord.Inventory.Grants,
    Rescord.Transfers.Grants,
    Rescord.Calendars.Grants,
    Rescord.Expenses.Grants,
    Rescord.Reports.Grants,
    Rescord.Ruby.Grants
  ]

# Configure the endpoint
config :rescord, RescordWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: RescordWeb.ErrorHTML, json: RescordWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Rescord.PubSub,
  live_view: [signing_salt: "ZuGQITIW"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# The store of the attachments (ADR 0038). `config/runtime.exs` gives
# `Rescord.Storage.S3` its endpoint and its keys, and the tests use a
# directory.
config :rescord, :storage, Rescord.Storage.S3

# The photos that go through libvips at the same time, and the milliseconds
# that a photo waits for its turn (ADR 0056). `config/runtime.exs` reads the
# slots of a server from `RESCORD_PHOTO_SLOTS`.
config :rescord, Rescord.Images.Limit, slots: 2, wait: 30_000

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :rescord, Rescord.Mailer, adapter: Swoosh.Adapters.Local

# esbuild bundles both app.js and the classless app.css, which imports one
# file per cascade layer (ADR 0004, ADR 0007).
# The version is required, and matches the esbuild of nixpkgs.
config :esbuild,
  version: "0.27.2",
  # Inside devenv, use esbuild from nixpkgs; otherwise it is downloaded.
  path: System.get_env("MIX_ESBUILD_PATH"),
  rescord: [
    args:
      ~w(js/app.js css/app.css --bundle --target=es2022 --outbase=. --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Cinder renders with our theme, which has almost no class (ADR 0014).
config :cinder, default_theme: RescordWeb.CinderTheme

# The sign-in (ADR 0018, ADR 0019). A link that does not work returns an
# error, and not an empty result.
config :ash_authentication, return_error_on_invalid_magic_link_token?: true

# The core builds the address of a sign-in link through the web layer, which
# it cannot name (ADR 0009). This names the function to call with the token.
config :rescord, :sign_in_link_url, {RescordWeb.SignInLink, :for_token}

# The same, for the address of the page where a person asks for a link. The
# email of an invitation names it.
config :rescord, :sign_in_page_url, {RescordWeb.SignInLink, :page}

# The sender of each email. A release sets its own in config/runtime.exs.
config :rescord, :mail_from, {"Rescord", "rescord@localhost"}

# A token is a credential: Phoenix keeps it out of the log of a request.
# The key of a provider is one too (ADR 0068): its field has the name
# `api_key`.
config :phoenix, :filter_parameters, ["password", "token", "api_key"]

# Configure Elixir's Logger. The fields say whose a line is (ADR 0077):
# `Rescord.Log.fields/0` names the same list, and a test holds the two
# together.
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user, :organisation, :job, :worker, :queue, :attempt]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
