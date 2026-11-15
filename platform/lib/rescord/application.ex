defmodule Rescord.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # The application starts both the core and the web layer, so it is a
  # boundary of its own, outside the core (ADR 0009).
  use Boundary, top_level?: true, deps: [Rescord, Rescord.Accounts, RescordWeb]

  @impl true
  def start(_type, _args) do
    children = [
      RescordWeb.Telemetry,
      Rescord.Repo,
      {DNSCluster, query: Application.get_env(:rescord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rescord.PubSub},
      # The counts of the rate limits (ADR 0020), in a table of this node.
      {Rescord.RateLimit, clean_period: :timer.minutes(1)},
      # Oban runs the background steps of the workflows (ADR 0010). It starts
      # after the repo, which holds its jobs, and after PubSub, so that a job
      # can publish.
      {Oban,
       AshOban.config(
         Application.fetch_env!(:rescord, :ash_domains),
         Application.fetch_env!(:rescord, Oban)
       )},
      # AshAuthentication removes the tokens that have expired (ADR 0018).
      {AshAuthentication.Supervisor, otp_app: :rescord},
      # The tasks of the requests for a sign-in link (ADR 0019). The limit stops
      # a flood of requests from starting a flood of tasks.
      {Task.Supervisor, name: Rescord.Accounts.sign_in_tasks(), max_children: 100},
      # Start to serve requests, typically the last entry
      RescordWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Rescord.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    RescordWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
