defmodule Rescord.Tasks.Workers.GenerateTasks do
  @moduledoc """
  The job that makes the tasks of the routines of each organisation
  (ADR 0033). Oban runs it each hour (`config/config.exs`).

  A day starts at a different hour in each time zone, so the job does not
  wait for one hour of the day. A routine that has its tasks up to its
  horizon costs no write.

  A fault in one organisation, such as a schema that a migration did not
  reach, goes to the log and does not stop the others.
  """

  require Logger

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for organisation <- Rescord.Accounts.all_organisations() do
      generate(organisation)
    end

    :ok
  end

  defp generate(organisation) do
    Rescord.Tasks.generate(organisation)
  rescue
    error ->
      Logger.error(
        "The routines of the organisation #{organisation.id} got no tasks: " <>
          Rescord.Log.reason(error)
      )
  end
end
