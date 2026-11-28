defmodule Rescord.Transfers.StoppedCopies do
  @moduledoc """
  Finds each transfer that is `sending` with no job that copies its files,
  and makes it `failed`, with `:interrupted` (ADR 0100). The person who
  sent it then sees "Send again" and "Withdraw".

  A transfer is `sending` with no job when the server stopped during the
  last try of its job: the lifeline of Oban finds that job `executing`
  after 2 hours, and discards it, because it has no try left. Before the
  lifeline, the job is still `executing`, so the transfer waits.

  The send and "Send again" write the job in their own transaction, so a
  transfer that is `sending` always has a job until that job ends. The
  `fail` of a transfer filters on the state `sending`, so a transfer that
  the job delivered in the meantime stays as it is.

  It reads the tables with no actor. `Rescord.Transfers.Workers.FailStoppedCopies`
  runs it each hour.
  """

  import Ecto.Query, only: [from: 2]

  require Ash.Query

  alias Rescord.Repo
  alias Rescord.Transfers.Transfer

  # The states of an Oban job that runs again, or runs now.
  @live ~w(available scheduled executing retryable)

  @doc "Makes each transfer whose job is gone `failed`, and returns how many."
  @spec run() :: {:ok, non_neg_integer} | {:error, term}
  def run do
    with {:ok, sending} <-
           Transfer
           |> Ash.Query.filter(state == :sending)
           |> Ash.Query.select([:id])
           |> Ash.read(authorize?: false) do
      live = live_jobs(Enum.map(sending, & &1.id))

      sending
      |> Enum.reject(&MapSet.member?(live, &1.id))
      |> Enum.reduce_while({:ok, 0}, fn transfer, {:ok, count} ->
        case fail(transfer) do
          :ok -> {:cont, {:ok, count + 1}}
          :stopped -> {:cont, {:ok, count}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  # The ids of the transfers that a job of `:transfer_started` still copies.
  defp live_jobs([]), do: MapSet.new()

  defp live_jobs(ids) do
    from(job in "oban_jobs",
      prefix: "public",
      where:
        job.worker == "AshOban.Signals.Worker" and job.state in @live and
          fragment("?->>'signal'", job.args) == "transfer_started" and
          fragment("?->'payload'->>'transfer_id'", job.args) in type(^ids, {:array, :string}),
      select: fragment("?->'payload'->>'transfer_id'", job.args)
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp fail(transfer) do
    transfer
    |> Ash.Changeset.for_update(:fail, %{failure: :interrupted}, authorize?: false)
    |> Ash.update()
    |> case do
      {:ok, _failed} ->
        :ok

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1)),
          do: :stopped,
          else: {:error, error}

      {:error, error} ->
        {:error, error}
    end
  end
end
