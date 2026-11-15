defmodule Rescord.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # The application starts both the core and the web layer, so it is a
  # boundary of its own, outside the core (ADR 0009).
  use Boundary, top_level?: true, deps: [Rescord, RescordWeb]

  @impl true
  def start(_type, _args) do
    children = [
      RescordWeb.Telemetry,
      Rescord.Repo,
      {DNSCluster, query: Application.get_env(:rescord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rescord.PubSub},
      # Oban runs the background steps of the workflows (ADR 0010). It starts
      # after the repo, which holds its jobs, and after PubSub, so that a job
      # can publish.
      {Oban,
       AshOban.config(
         Application.fetch_env!(:rescord, :ash_domains),
         Application.fetch_env!(:rescord, Oban)
       )},
      # Start a worker by calling: Rescord.Worker.start_link(arg)
      # {Rescord.Worker, arg},
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
