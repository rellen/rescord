defmodule RescordWeb.Telemetry do
  @moduledoc """
  The metrics of Rescord, and the endpoint that a collector reads (ADR 0077).

  `metrics/0` is the whole list: the requests and the pages, and the metrics
  of the core (`Rescord.Metrics`). LiveDashboard draws it in development.

  A release measures nothing by default. When the operator sets
  `RESCORD_METRICS_PORT`, this supervisor starts a reporter (Peep), and a
  small web server on that port that answers `GET /metrics` in the format
  of Prometheus, and 404 for each other path. The port is not the port of
  the pages, so a reverse proxy does not publish it. The metrics have no
  sign-in: keep the port inside the network of the server.

  See `Rescord.Metrics` for the rule about the tags.
  """

  use Supervisor

  import Telemetry.Metrics

  alias Rescord.Metrics

  @reporter __MODULE__.Reporter

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    settings = Application.get_env(:rescord, __MODULE__, [])

    # Ash measures an action only while something listens: the reporter, or
    # LiveDashboard in development.
    if settings[:port] || Application.get_env(:rescord, :dev_routes), do: Metrics.attach()

    # The measurements of the VM come from the application `telemetry_poller`,
    # which emits them with no child here.
    Supervisor.init(reporter(settings), strategy: :one_for_one)
  end

  @doc """
  The children that report the metrics: the reporter, and the web server of
  `/metrics` on `:port` and `:ip`. With no port there is none.
  """
  @spec reporter(keyword) :: [Supervisor.child_spec() | {module, keyword}]
  def reporter(settings) do
    case settings[:port] do
      nil ->
        []

      port ->
        [
          {Peep, name: @reporter, metrics: metrics()},
          {Bandit,
           plug: {Peep.Plug, peep_worker: @reporter, on_unmatched_path: :halt},
           scheme: :http,
           ip: Keyword.get(settings, :ip, {127, 0, 0, 1}),
           port: port}
        ]
    end
  end

  @doc "Each metric of Rescord, as `Telemetry.Metrics` definitions."
  @spec metrics() :: [struct]
  def metrics do
    [
      Metrics.duration("rescord.http.request.duration.milliseconds",
        event_name: [:phoenix, :endpoint, :stop],
        measurement: :duration,
        tags: [:status],
        tag_values: &%{status: &1.conn.status},
        description: "The time of a request, by the status of its answer"
      ),
      Metrics.duration("rescord.http.route.duration.milliseconds",
        event_name: [:phoenix, :router_dispatch, :stop],
        measurement: :duration,
        tags: [:route],
        description: "The time of a request in its controller or page, by route"
      ),
      counter("rescord.http.exception.count",
        event_name: [:phoenix, :router_dispatch, :exception],
        tags: [:route],
        description: "The requests that stopped with a fault"
      ),
      Metrics.duration("rescord.page.mount.duration.milliseconds",
        event_name: [:phoenix, :live_view, :mount, :stop],
        measurement: :duration,
        tags: [:view],
        tag_values: &view/1,
        description: "The time that a page takes to open"
      ),
      counter("rescord.page.mount.exception.count",
        event_name: [:phoenix, :live_view, :mount, :exception],
        tags: [:view],
        tag_values: &view/1,
        description: "The pages that stopped with a fault when they opened"
      ),
      Metrics.duration("rescord.page.event.duration.milliseconds",
        event_name: [:phoenix, :live_view, :handle_event, :stop],
        measurement: :duration,
        tags: [:view],
        tag_values: &view/1,
        description: "The time of an event of a page"
      ),
      counter("rescord.page.event.exception.count",
        event_name: [:phoenix, :live_view, :handle_event, :exception],
        tags: [:view],
        tag_values: &view/1,
        description: "The pages that stopped with a fault in an event"
      )
    ] ++ Metrics.metrics()
  end

  # The module of the page. The name of the event is not a tag: a client
  # sends it.
  defp view(%{socket: socket}), do: %{view: inspect(socket.view)}
end
