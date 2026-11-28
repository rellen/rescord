defmodule Rescord.Log.Jobs do
  @moduledoc """
  The lines of the log for the jobs of Oban (ADR 0077).

  Oban keeps the error of a job in the row of the job, and writes no line.
  This handler listens to the events of Oban:

    * When a job starts, it sets the fields of the log for the process of
      the job: the id of the job, the worker, the queue, the try, and the
      organisation when the job has a tenant.
    * When a job fails, it writes a warning while Oban tries the job again,
      and an error for the last try.
    * When a job is cancelled or discarded by its worker, it writes a
      warning.
    * When a plugin of Oban fails, such as the one that makes the hourly
      job, it writes an error.

  A line never holds the arguments of a job: the job of an invitation holds
  the address of a person. So this is not the logger of Oban
  (`Oban.Telemetry.attach_default_logger/1`), which writes them.
  """

  require Logger

  alias Rescord.Log

  @handler "rescord-log-jobs"

  @events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception],
    [:oban, :plugin, :exception]
  ]

  @doc "Starts to listen. A second call changes nothing."
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach_many(@handler, @events, &__MODULE__.handle/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc false
  def handle([:oban, :job, :start], _measurements, %{job: job}, _config) do
    Log.context(
      [job: job.id, worker: job.worker, queue: job.queue, attempt: job.attempt] ++
        organisation(job.args)
    )
  end

  def handle([:oban, :job, :exception], _measurements, %{job: job} = meta, _config) do
    reason = Log.reason(meta[:reason])
    trace = trace(meta[:stacktrace])
    tries = "try #{job.attempt} of #{job.max_attempts}"

    case meta[:state] do
      :discard ->
        Logger.error(
          "The job #{job.id} of #{job.worker} failed on #{tries}, the last one: #{reason}#{trace}"
        )

      _again ->
        Logger.warning(
          "The job #{job.id} of #{job.worker} failed on #{tries}, and runs again later: " <>
            "#{reason}#{trace}"
        )
    end
  end

  def handle([:oban, :job, :stop], _measurements, %{job: job, state: state} = meta, _config)
      when state in [:cancelled, :discard] do
    reason = Log.reason(meta[:result])
    Logger.warning("The job #{job.id} of #{job.worker} stopped as #{state}: #{reason}")
  end

  def handle([:oban, :job, :stop], _measurements, _meta, _config), do: :ok

  def handle([:oban, :plugin, :exception], _measurements, meta, _config) do
    plugin = Shoddy.Terms.shape(meta[:plugin])
    reason = Log.reason(meta[:reason] || meta[:error])
    Logger.error("The plugin #{plugin} of Oban failed: #{reason}#{trace(meta[:stacktrace])}")
  end

  # The tenant of a job of an organisation is the name of its schema.
  defp organisation(%{"tenant" => "org_" <> id}), do: [organisation: id]
  defp organisation(_arguments), do: []

  defp trace([_ | _] = frames), do: "\n" <> Log.stacktrace(frames)
  defp trace(_none), do: ""
end
