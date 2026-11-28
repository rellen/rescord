defmodule Rescord.Health.Checks.Jobs do
  @moduledoc """
  C9 of issue 38: the jobs of Oban. One query of `oban_jobs`:

  - a fault: a job that waits to start for more than 15 minutes (the
    queues are stuck, or no node runs them), or a job that has run for
    more than 30 minutes (the lifeline takes it back only after 2 hours);
  - a note: a job that failed and runs again later (`retryable`), and a job
    that failed its last try in the last day (`discarded`). The pruner
    deletes the rows of a job after a day.

  The count is the number of such jobs. A job has no uuid, so the ids are
  empty, and the log of each job (`Rescord.Log.Jobs`) names its worker.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :jobs
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Jobs that are stuck, or that failed"

  @impl true
  def explain,
    do:
      "A fault: jobs wait to start for more than 15 minutes, or have run for more than " <>
        "30 minutes. A note: jobs failed and run again, or failed for the last time today. " <>
        "The log names the worker of each failure."

  @impl true
  def run(%{now: now}) do
    %{rows: [[stuck, failed]]} =
      Rescord.Repo.query!(
        """
        select
          count(*) filter (where
            (state = 'available' and scheduled_at < $1::timestamp - interval '15 minutes')
            or (state = 'executing' and attempted_at < $1::timestamp - interval '30 minutes')),
          count(*) filter (where
            state = 'retryable'
            or (state = 'discarded' and discarded_at > $1::timestamp - interval '1 day'))
        from public.oban_jobs
        where state in ('available', 'executing', 'retryable', 'discarded')
        """,
        [DateTime.to_naive(now)]
      )

    cond do
      stuck > 0 -> %{level: :fail, count: stuck + failed, ids: []}
      failed > 0 -> %{level: :note, count: failed, ids: []}
      true -> ok()
    end
  end
end
