defmodule Rescord.MixProject do
  use Mix.Project

  def project do
    [
      app: :rescord,
      version: "0.2.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      usage_rules: usage_rules(),
      # `:ash_signals` finds the listeners of each signal one time, at the build
      # (ADR 0067). It comes after `:boundary`.
      compilers: [:boundary, :ash_signals, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      releases: releases(),
      # `mix hex.audit` runs in CI and fails on an advisory (ADR 0048).
      # EEF-CVE-2026-117656 is in the Sign in with Apple code of assent 0.2,
      # which ash_authentication 4.15 locks below 0.3. Rescord has no OAuth
      # strategy and never calls that code. Take this out when
      # ash_authentication allows assent 0.3.2 or later.
      hex: [ignore_advisories: ["EEF-CVE-2026-117656"]],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Rescord.Application, []},
      # xmerl reads the list of the files of a bucket (ADR 0059).
      extra_applications: [:logger, :runtime_tools, :xmerl]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test, "test.mutation": :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # What `mix usage_rules.sync` writes into platform/AGENTS.md (ADR 0008).
  # The file is inside the Mix project because the links that the task
  # writes are relative to it.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        # Inlined: how to search the docs, and the built-in Elixir and OTP rules.
        :usage_rules,
        # Linked: the rules of every other dependency that ships them.
        {~r/^(?!usage_rules$)/, link: :markdown}
      ]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash_archival, "~> 2.0"},
      {:ash_paper_trail, "~> 0.8"},
      {:ash_state_machine, "~> 0.2"},
      {:ash_oban, "~> 0.2"},
      {:oban, "~> 2.0"},
      {:ash_workflow, "~> 0.12"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:ash_boundary, "~> 0.2.0"},
      {:cinder, "~> 0.18"},
      {:ash_authentication, "~> 4.15"},
      # Ash needs a SAT solver for its policies. This one is plain Elixir.
      {:simple_sat, "~> 0.1"},
      # The time zone rules, for the time zone of an organisation (ADR 0026).
      {:tz, "~> 0.28"},
      {:ash_rate_limiter, "~> 2.0"},
      # The assistant, Ruby (ADR 0069): the tools and the loop of a model, and
      # the requests to a provider.
      {:ash_ai, "~> 1.5"},
      {:req_llm, "~> 1.31"},
      # The secrets of a settings resource (ADR 0068). The vault is
      # `Rescord.Vault`, and not the package `cloak`.
      {:ash_cloak, "~> 0.5"},
      {:mdex, "~> 0.14"},
      # The amounts of the expenses (ADR 0082): a decimal with its currency, and
      # its type in PostgreSQL. `ex_money` writes an amount with Localize.
      {:ash_money, "~> 0.2.8"},
      {:ex_money, "~> 6.3"},
      {:ex_money_sql, "~> 2.2"},
      {:hammer, "~> 7.5"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:usage_rules, "~> 1.3", only: [:dev]},
      {:phoenix, "~> 1.8.16"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      # The browser tests (ADR 0023).
      {:phoenix_test, "~> 0.14.0", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.19.0", only: :test, runtime: false},
      # The rules of axe-core, which a browser test holds each page to
      # (ADR 0090). The package carries the script of axe-core.
      {:a11y_audit, "~> 0.6.0", only: :test},
      # Mutation testing, with `mix test.mutation` (ADR 0100).
      {:muex, "~> 0.13", only: [:dev, :test], runtime: false},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      # Not on Hex, so pinned to a commit (ADR 0005).
      {:shoddy, github: "rellen/shoddy", ref: "d49e059538ce4ef2db6518353cf7d5852eb2d386"},
      {:shoddy_phoenix,
       github: "rellen/shoddy_phoenix", ref: "5ff4a14c61739faf9f2de557582e2a9efefe4110"},
      {:swoosh, "~> 1.16"},
      # SMTP for the adapter of Swoosh: each operator names a mail server (ADR 0044).
      {:gen_smtp, "~> 1.2"},
      # The HTML part of an email: MJML with EEx, through the Rust NIF of mrml
      # (ADR 0070).
      {:mjml_eex, "~> 0.13.0"},
      {:req, "~> 0.5"},
      # The store of the attachments, compatible with S3 (ADR 0038).
      {:req_s3, "~> 0.2.5"},
      # The photos of a resident: their metadata, rotation and thumbnails,
      # through libvips (ADR 0055).
      {:image, "~> 0.74"},
      # The reports as PDF: Typst, with its compiler as a native library
      # (ADR 0076).
      {:ash_typst, "~> 0.6.1"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      # The reporter of the metrics, in the format of Prometheus (ADR 0077).
      {:peep, "~> 6.0"},
      {:gettext, "~> 1.0"},
      # The forms of a date, a time and a number in the locale of an
      # organisation, from the data of CLDR (ADR 0075).
      {:localize, "~> 1.11"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.1"},
      {:bandit, "~> 1.5"}
    ]
  end

  # The release (ADR 0044): the same build for the Docker image, the Nix
  # package and the tarball. Each one runs `bin/migrate` before `bin/server`.
  defp releases do
    [
      rescord: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # A browser test loads app.js and app.css, so the tests build them first.
      # A run of muex skips both: see `muex_command/0`.
      test: test_setup() ++ ["test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild rescord"],
      "assets.deploy": [
        "esbuild rescord --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      # Mutation testing with muex (ADR 0100). `mix precommit` and CI do not
      # run it, and with --fail-at 0 a low score does not make it fail. Give
      # it what to mutate: `mix test.mutation --files lib/rescord/units`.
      "test.mutation": [&mark_mutation_run/1, muex_command()]
    ]
  end

  # muex runs `mix test` for each mutant, in a copy of the project (a
  # sandbox) that has no `assets/`. The set-up of the alias `test` would then
  # fail, and it would cost seconds for each mutant. So `mix test.mutation`
  # sets RESCORD_MUTATION_RUN, each `mix test` of muex inherits it, and its
  # alias `test` skips the set-up. The workflow and a person set up the test
  # database and the assets once, before the run.
  @mutation_run "RESCORD_MUTATION_RUN"

  defp test_setup do
    if System.get_env(@mutation_run) == "1",
      do: [],
      else: ["ash.setup --quiet", "assets.build"]
  end

  defp mark_mutation_run(_args), do: System.put_env(@mutation_run, "1")

  # muex chooses, for each mutant, the test files that name the mutated
  # module. The browser tests are left out: each starts a browser, which
  # costs seconds for each mutant. A mutant of a page takes the LiveView
  # tests.
  #
  # --no-tce: the check of muex 0.13.1 for a mutant that compiles to the
  # same code compares the first module that the file compiles. For a module
  # with a `defimpl` or a module inside it, that is the inner module, so it
  # calls nearly each mutant of the outer module equivalent and runs no test
  # (ADR 0100). --timeout is the time with no output from `mix test`: a
  # mutant of a domain recompiles hundreds of files, and at 60 seconds four
  # such mutants timed out on 4 cores.
  defp muex_command do
    test_files =
      Path.wildcard("test/**/*_test.exs") -- Path.wildcard("test/rescord_web/features/**")

    Enum.join(
      ["muex --fail-at 0 --timeout 180000 --no-tce --test-paths", Enum.join(test_files, ",")],
      " "
    )
  end
end
