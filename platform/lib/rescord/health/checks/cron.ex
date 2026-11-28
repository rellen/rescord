defmodule Rescord.Health.Checks.Cron do
  @moduledoc """
  C10 of issue 38: a job of the crontab that runs each hour and has not
  ended well in the last 2 hours. It reads the crontab of the config, so a
  new hourly job is checked with no change here, and the rows of
  `oban_jobs`, which the pruner keeps for a day. A daily job is not
  checked here: a day of rows cannot tell a missed run from a pruned one.

  A server that started less than 3 hours ago has had no chance to run
  each job twice, so the check finds nothing then.
  """

  use Rescord.Health.Check

  @window_hours 2
  @young_ms 3 * 3_600_000

  @impl true
  def name, do: :cron
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Hourly jobs that stopped"

  @impl true
  def explain,
    do:
      "The count of hourly jobs of the crontab with no run that ended well in the last " <>
        "2 hours. Look in the log for the worker, and at the check of the jobs."

  @impl true
  def run(context) do
    uptime = Map.get_lazy(context, :uptime_ms, fn -> elem(:erlang.statistics(:wall_clock), 0) end)

    if uptime < @young_ms do
      ok()
    else
      stopped = Enum.reject(hourly_workers(), &ran?(&1, context.now))
      if stopped == [], do: ok(), else: %{level: :fail, count: length(stopped), ids: []}
    end
  end

  @doc "The workers of the crontab whose expression runs once each hour."
  @spec hourly_workers() :: [String.t()]
  def hourly_workers do
    crontab = get_in(Application.get_env(:rescord, Oban, []), [:cron, :crontab]) || []

    for entry <- crontab,
        {expression, worker} = {elem(entry, 0), elem(entry, 1)},
        hourly?(expression),
        do: worker |> Module.split() |> Enum.join(".")
  end

  defp hourly?(expression) do
    case String.split(expression) do
      [minute, "*", "*", "*", "*"] -> match?({_n, ""}, Integer.parse(minute))
      _other -> false
    end
  end

  defp ran?(worker, now) do
    %{rows: [[ran?]]} =
      Rescord.Repo.query!(
        """
        select exists (
          select 1 from public.oban_jobs
          where worker = $1 and state = 'completed'
            and completed_at > $2::timestamp - make_interval(hours => $3))
        """,
        [worker, DateTime.to_naive(now), @window_hours]
      )

    ran?
  end
end
