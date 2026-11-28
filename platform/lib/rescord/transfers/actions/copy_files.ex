defmodule Rescord.Transfers.Actions.CopyFiles do
  @moduledoc """
  Copies the files of a transfer that is `sending` (ADR 0100). A job runs
  it for `:transfer_started`, after the commit of the send, and again
  after a fault. It has no transaction: a database connection is held for
  the short writes of the count and of the end alone.

  1. It reads the transfer. In a state other than `sending` it does
     nothing: the person withdrew it, or another job delivered it.
  2. It copies each source that is not copied yet, one at a time, from
     the store of the refuge that sent it to the key of the transfer
     (`Rescord.Transfers.Files.copy_one/3`). `files_copied` counts the
     first sources that are there, so a new try starts at the count.
  3. It writes the count at most once each 2 seconds (`progress`). Each
     write tells the pages of both refuges to read again (ADR 0096), so a
     copy of many small files does not make them read for each file. When
     the transfer that the write returns is no longer `sending`, the job
     stops there. The count is written in that state too, so the file
     check names each file that the job put (ADR 0091).
  4. After the last file it runs `deliver`: the transfer is `sent`.

  A fault:

    * a source that the store of the refuge that sent it does not have:
      the transfer `failed` at once, with `:file_missing`. Another try
      cannot help;
    * any other fault, of a store or of the database: the count is
      written, and the action returns the error, so Oban tries again
      later. On the last try of the job the transfer `failed`, with
      `:store_refused`, and the job ends, so no transfer stays `sending`
      with no job.

  The nested writes carry the signal path of the job, so their policy is
  the signal too, and no person's grant.
  """

  use Ash.Resource.Actions.Implementation

  require Logger

  alias Rescord.Transfers.{Files, Transfer}

  @impl true
  def run(input, _opts, context) do
    signal = Ash.ActionInput.get_argument(input, :signal)
    opts = [authorize?: context.authorize?, context: %{signal_path: input.context[:signal_path]}]
    last_try? = last_try?(input)

    case read(signal.transfer_id) do
      {:ok, %Transfer{state: :sending} = transfer} ->
        transfer |> copy(opts) |> finish(transfer, last_try?, opts)

      {:ok, _not_sending} ->
        :ok

      {:error, error} ->
        give_up_or(error, signal.transfer_id, last_try?, opts)
    end
  end

  # The job of Oban, which AshOban gives the action (`shared_context:
  # [:job]`). An action that runs with no job has one try.
  defp last_try?(input) do
    case input.context[:ash_oban][:job] do
      %{attempt: attempt, max_attempts: max} -> attempt >= max
      _no_job -> true
    end
  end

  # `{:done, copied}`, `{:stopped, copied}`, `{:missing, copied}` or
  # `{:error, error, copied}`, with the number of the first sources that
  # are in the store.
  defp copy(transfer, opts) do
    sources = transfer.sources || []
    total = length(sources)
    started = System.monotonic_time(:millisecond)

    sources
    |> Enum.with_index(1)
    |> Enum.drop(transfer.files_copied)
    |> Enum.reduce_while({:copying, transfer.files_copied, started}, fn {source, number},
                                                                        {:copying, _copied, at} ->
      case copy_one(source, transfer) do
        :ok -> after_copy(transfer, number, total, at, opts)
        {:error, :not_found} -> {:halt, {:missing, number - 1}}
        {:error, error} -> {:halt, {:error, error, number - 1}}
      end
    end)
    |> case do
      {:copying, copied, _at} -> {:done, copied}
      halted -> halted
    end
  end

  defp copy_one(source, transfer) do
    Files.copy_one(source, transfer.to_organisation_id, transfer.id)
  rescue
    error -> {:error, error}
  end

  defp after_copy(transfer, number, total, at, opts) do
    now = System.monotonic_time(:millisecond)

    if now - at >= interval() and number < total do
      case progress(transfer, number, opts) do
        :ok -> {:cont, {:copying, number, now}}
        :stopped -> {:halt, {:stopped, number}}
        {:error, error} -> {:halt, {:error, error, number}}
      end
    else
      {:cont, {:copying, number, at}}
    end
  end

  defp finish({:done, copied}, transfer, last_try?, opts) do
    transfer
    |> Ash.Changeset.for_update(:deliver, %{}, opts)
    |> Ash.update()
    |> case do
      {:ok, _sent} ->
        :ok

      error ->
        case stopped_or(error) do
          # A person withdrew it during the last file: the count names it.
          :stopped -> stopped(transfer, copied, opts)
          {:error, error} -> fault(error, transfer, copied, last_try?, opts)
        end
    end
  end

  defp finish({:stopped, _copied}, _transfer, _last_try?, _opts), do: :ok

  defp finish({:missing, copied}, transfer, _last_try?, opts) do
    Logger.warning("A file of a transfer is not in the store of the refuge that sent it")

    case progress(transfer, copied, opts) do
      :stopped -> :ok
      _written_or_not -> fail(transfer.id, :file_missing, opts)
    end
  end

  defp finish({:error, error, copied}, transfer, last_try?, opts),
    do: fault(error, transfer, copied, last_try?, opts)

  defp fault(error, transfer, copied, last_try?, opts) do
    Logger.warning("The copy of the files of a transfer failed: #{Rescord.Log.reason(error)}")

    case progress(transfer, copied, opts) do
      :stopped -> :ok
      _written_or_not -> give_up_or(error, transfer.id, last_try?, opts)
    end
  end

  defp stopped(transfer, copied, opts) do
    progress(transfer, copied, opts)
    :ok
  end

  # On the last try the transfer `failed`, and the job ends. Before it, the
  # error goes back to Oban, which tries again later.
  defp give_up_or(_error, transfer_id, true = _last_try?, opts),
    do: fail(transfer_id, :store_refused, opts)

  defp give_up_or(error, _transfer_id, false = _last_try?, _opts), do: {:error, error}

  # Writes the count, and says whether the transfer is still `sending`. The
  # write finds no transfer when its sources are gone: another job
  # delivered it.
  defp progress(transfer, count, opts) do
    if count > transfer.files_copied do
      transfer
      |> Ash.Changeset.for_update(:progress, %{files_copied: count}, opts)
      |> Ash.update()
      |> case do
        # The record that a non-atomic update returns holds the state that
        # the job read, so the state of now comes from a read.
        {:ok, _written} -> still_sending(transfer.id)
        error -> stopped_or(error)
      end
    else
      still_sending(transfer.id)
    end
  end

  # The filter of `fail` holds the state `sending`: a transfer in another
  # state stays as it is.
  defp fail(transfer_id, failure, opts) do
    with {:ok, %Transfer{} = transfer} <- read(transfer_id) do
      transfer
      |> Ash.Changeset.for_update(:fail, %{failure: failure}, opts)
      |> Ash.update()
      |> case do
        {:ok, _failed} -> :ok
        error -> with :stopped <- stopped_or(error), do: :ok
      end
    else
      {:ok, nil} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  # A write whose filter finds no record returns a stale record.
  defp stopped_or({:error, %Ash.Error.Invalid{errors: errors} = error}) do
    if Enum.any?(errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1)),
      do: :stopped,
      else: {:error, error}
  end

  defp stopped_or({:error, error}), do: {:error, error}

  # The policy of the read is for a person (`Checks.MemberOf`). The job
  # reads the transfer that its signal names, and nothing else.
  defp read(id), do: Ash.get(Transfer, id, authorize?: false, not_found_error?: false)

  defp still_sending(id) do
    case read(id) do
      {:ok, %Transfer{state: :sending}} -> :ok
      {:ok, _other} -> :stopped
      {:error, error} -> {:error, error}
    end
  end

  # How long the job waits between two writes of the count, in
  # milliseconds. The tests write after each file.
  defp interval,
    do: Application.get_env(:rescord, __MODULE__, []) |> Keyword.get(:progress_every, 2_000)
end
