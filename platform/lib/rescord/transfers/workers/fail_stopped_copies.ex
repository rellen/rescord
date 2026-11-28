defmodule Rescord.Transfers.Workers.FailStoppedCopies do
  @moduledoc """
  The job that makes each transfer whose copy stopped for good `failed`
  (ADR 0100, `Rescord.Transfers.StoppedCopies`). Oban runs it each hour
  (`config/config.exs`).
  """

  require Logger

  use Oban.Worker, queue: :default, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Rescord.Transfers.fail_stopped_copies() do
      {:ok, 0} ->
        :ok

      {:ok, count} ->
        Logger.warning("Transfers whose copy stopped and did not start again: #{count}")
        :ok

      {:error, error} ->
        {:error, error}
    end
  end
end
