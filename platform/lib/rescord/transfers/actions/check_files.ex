defmodule Rescord.Transfers.Actions.CheckFiles do
  @moduledoc """
  Checks the files of an imported transfer before they open (issue 37,
  ADR 0113). A job runs it for `:transfer_imported`, after the commit of
  the import, and again after a fault. The import put the files in the
  store as the other server sent them; until this action ends, the files
  stay closed (`Rescord.Transfers.files_open?/1`).

  For each file that the copy names, one at a time:

    * a photo, or the thumbnail of one, is written again from its pixels
      (`Rescord.Images.clean/1`): no metadata, nothing after the image. It
      goes back under its key, and the copy gets its new size
      (`Rescord.Transfers.Files.put_file_size/3`);
    * a PDF goes to the virus scan when it is on
      (`Rescord.Storage.Scan.check/1`).

  Then `files_checked` writes `files_checked_at`, and the files open. A
  file that fails stops the check, and `files_checked` writes the reason,
  `files_check_failure`: each file of the copy stays closed, and the
  receiver can decline the transfer. The reasons:

    * `:unreadable`: a photo that libvips cannot read, or a file that is
      not in the store after the 10 tries of the job;
    * `:infected`: a PDF that clamd found harmful;
    * `:unscanned`: a clamd that did not answer in the 10 tries.

  A photo that waits for a slot of libvips waits again, here; a fault of
  the store or of clamd returns an error, and Oban tries again later. A new
  try writes the photos of the first try again: a JPEG loses a little more
  at each try, which a fault of the store alone causes.

  The nested writes carry the signal path of the job, so their policy is
  the signal too, and no person's grant.
  """

  use Ash.Resource.Actions.Implementation

  require Logger

  alias Rescord.{Images, Storage}
  alias Rescord.Storage.Errors.RefusedFile
  alias Rescord.Storage.Scan
  alias Rescord.Transfers.{Files, Snapshot, Transfer}

  # A photo that finds each slot of libvips taken waits this long, at most
  # this many times, before the job tries again later.
  @busy_wait 2_000
  @busy_tries 30

  @impl true
  def run(input, _opts, context) do
    signal = Ash.ActionInput.get_argument(input, :signal)
    opts = [authorize?: context.authorize?, context: %{signal_path: input.context[:signal_path]}]

    case read(signal.transfer_id) do
      {:ok, %Transfer{files_checked_at: nil, files_check_failure: nil} = transfer} ->
        transfer |> check() |> finish(transfer, last_try?(input), opts)

      {:ok, _checked_or_gone} ->
        :ok

      {:error, error} ->
        {:error, error}
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

  # `:ok`, `{:failed, reason}` for a file that cannot pass, or
  # `{:retry, reason, error}` for a fault that a later try can mend.
  defp check(transfer) do
    transfer.snapshot
    |> Snapshot.files()
    |> Enum.reduce_while(:ok, fn file, :ok ->
      case check_one(transfer, file) do
        :ok -> {:cont, :ok}
        stop -> {:halt, stop}
      end
    end)
  end

  defp check_one(transfer, %{"id" => file_id} = file) when is_binary(file_id) do
    key = Files.key(transfer.to_organisation_id, transfer.id, file_id)

    case Storage.get(key) do
      {:ok, bytes} -> check_bytes(transfer, file, key, bytes)
      {:error, error} -> {:retry, :unreadable, error}
    end
  end

  defp check_one(_transfer, _file), do: {:failed, :unreadable}

  defp check_bytes(transfer, file, key, bytes) do
    case Storage.Upload.type_of(bytes) do
      "application/pdf" -> scan(bytes)
      nil -> {:failed, :unreadable}
      type -> clean(transfer, file, key, bytes, type, @busy_tries)
    end
  end

  defp scan(bytes) do
    case Scan.check(%{content_type: "application/pdf", bytes: bytes}) do
      :ok -> :ok
      {:error, %RefusedFile{reason: :infected}} -> {:failed, :infected}
      {:error, %RefusedFile{reason: :unscanned} = error} -> {:retry, :unscanned, error}
    end
  end

  defp clean(transfer, file, key, bytes, type, tries) do
    case Images.clean(bytes) do
      {:ok, cleaned} ->
        with :ok <- Storage.put(key, cleaned, type) do
          Files.put_file_size(transfer.id, file["id"], byte_size(cleaned))
        else
          {:error, error} -> {:retry, :unreadable, error}
        end

      {:error, %RefusedFile{reason: :busy} = error} when tries <= 1 ->
        {:retry, :unreadable, error}

      {:error, %RefusedFile{reason: :busy}} ->
        Process.sleep(@busy_wait)
        clean(transfer, file, key, bytes, type, tries - 1)

      {:error, %RefusedFile{}} ->
        {:failed, :unreadable}
    end
  end

  defp finish(:ok, transfer, _last_try?, opts), do: checked(transfer, nil, opts)

  defp finish({:failed, reason}, transfer, _last_try?, opts) do
    Logger.warning("A file of an imported transfer failed its check: #{reason}")
    checked(transfer, reason, opts)
  end

  defp finish({:retry, reason, _error}, transfer, true = _last_try?, opts),
    do: finish({:failed, reason}, transfer, false, opts)

  defp finish({:retry, _reason, error}, _transfer, false = _last_try?, _opts) do
    Logger.warning("The check of the files of an import waits: #{Rescord.Log.reason(error)}")
    {:error, error}
  end

  # The filter of `files_checked` holds a check that has not ended: a
  # second job that ended it first leaves the record as it is.
  defp checked(transfer, failure, opts) do
    transfer
    |> Ash.Changeset.for_update(:files_checked, %{failure: failure}, opts)
    |> Ash.update()
    |> case do
      {:ok, _checked} ->
        :ok

      {:error, %Ash.Error.Invalid{errors: errors} = error} ->
        if Enum.any?(errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1)),
          do: :ok,
          else: {:error, error}

      {:error, error} ->
        {:error, error}
    end
  end

  # The policy of the read is for a person (`Checks.MemberOf`). The job
  # reads the transfer that its signal names, and nothing else.
  defp read(id), do: Ash.get(Transfer, id, authorize?: false, not_found_error?: false)
end
