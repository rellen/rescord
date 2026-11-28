defmodule Rescord.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # The application starts both the core and the web layer, so it is a
  # boundary of its own, outside the core (ADR 0009).
  use Boundary,
    top_level?: true,
    deps: [Rescord, Rescord.Accounts, Rescord.Ruby, Rescord.Usage, RescordWeb]

  @impl true
  def start(_type, _args) do
    # libvips reads the photos that people send: it uses no loader that its
    # authors do not trust with such a file (ADR 0055).
    :ok = Rescord.Images.block_untrusted()

    # The crash reports hold no message of a process, and a job that fails
    # writes a line (ADR 0077).
    :ok = Rescord.Log.attach()

    # The usage counts (ADR 0098): the actions of Ash, and the pages and the
    # files of the web layer. A handler does nothing in the mode `off`.
    :ok = Rescord.Usage.Actions.attach()
    :ok = RescordWeb.Usage.attach()

    children = [
      RescordWeb.Telemetry,
      Rescord.Repo,
      {DNSCluster, query: Application.get_env(:rescord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Rescord.PubSub},
      # The counts of the rate limits (ADR 0020), in a table of this node.
      {Rescord.RateLimit, clean_period: :timer.minutes(1)},
      # The usage counts of this node in memory, which it writes to the
      # database each minute (ADR 0098). It starts after the repo.
      Rescord.Usage.Counter,
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
      # The slots of libvips (ADR 0056): only a few photos go through it at
      # the same time, so that a batch of large photos cannot fill the memory.
      Rescord.Images.Limit,
      # The model catalogue of the assistant, when the server has a provider
      # (ADR 0069). The task runs one time, and is not started again.
      Supervisor.child_spec({Task, &Rescord.Ruby.warm_up/0}, id: :ruby_warm_up),
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
