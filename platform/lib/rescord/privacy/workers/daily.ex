defmodule Rescord.Privacy.Workers.Daily do
  @moduledoc """
  The daily work of privacy in each organisation (ADR 0105): the holds of
  the money records that ended, the closed requests that are old enough
  to go, and the pseudonymisation after the months of the settings
  (`Rescord.Privacy.daily/1`). Oban runs it each day (`config/config.exs`).

  A fault in one organisation goes to the log and does not stop the others.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for organisation <- Rescord.Accounts.all_organisations(), do: run(organisation)
    :ok
  end

  defp run(organisation) do
    Rescord.Privacy.daily(organisation)
  rescue
    error ->
      Logger.error(
        "The daily work of privacy of the organisation #{organisation.id} failed: " <>
          Rescord.Log.reason(error)
      )
  end
end
