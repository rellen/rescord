defmodule Rescord.Transfers.Changes.StartCheck do
  @moduledoc """
  Starts the check of the files of an import (issue 37, ADR 0113). The
  files arrive as the other server sent them, so they stay closed until a
  job has written each photo again with no metadata, and scanned each PDF
  when the virus scan is on (`Rescord.Transfers.Actions.CheckFiles`).

  After the write of the import, in its transaction, the change emits
  `:transfer_imported`. Oban writes the job in that transaction, so the
  job is there only when the transfer is, and it runs after the commit. A
  copy with no file needs no check: it gets `files_checked_at` at once,
  and emits nothing.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Rescord.Transfers.Snapshot

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Changeset.before_action(fn changeset ->
      case Snapshot.files(Changeset.get_attribute(changeset, :snapshot) || %{}) do
        [] -> Changeset.force_change_attribute(changeset, :files_checked_at, DateTime.utc_now())
        _files -> changeset
      end
    end)
    |> Changeset.after_action(fn changeset, transfer ->
      if is_nil(transfer.files_checked_at) do
        case Ash.Signals.emit(
               changeset,
               Rescord.Transfers.Signals,
               :transfer_imported,
               %{transfer_id: transfer.id},
               actor: nil
             ) do
          :ok -> {:ok, transfer}
          {:error, error} -> {:error, error}
        end
      else
        {:ok, transfer}
      end
    end)
  end
end
