defmodule Rescord.MixProject do
  use Mix.Project

  def project do
    [
      app: :rescord,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      usage_rules: usage_rules(),
      compilers: [:boundary, :phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Rescord.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
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
      {:ash_rate_limiter, "~> 2.0"},
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
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      # Not on Hex, so pinned to a commit (ADR 0005).
      {:shoddy, github: "rellen/shoddy", ref: "3feca9cf084710e7dac7eda95a39379ae517fc08"},
      {:shoddy_phoenix,
       github: "rellen/shoddy_phoenix", ref: "acb06970c7138063303bdad28a3b2d699fef6e76"},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
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
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["compile", "esbuild rescord"],
      "assets.deploy": [
        "esbuild rescord --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
