defmodule Rescord.Transfers.Changes.StartCopy do
  @moduledoc """
  Emits `:transfer_started` after the write of a transfer that is
  `sending` (ADR 0100): `send` and `send_again`. The listener of
  `Rescord.Transfers.Transfer` runs in a job, which Oban writes in the
  transaction of the action, so the job is there only when the transfer
  is, and it runs after the commit.

  A transfer that is `sent` at once, with no file, emits nothing.

  The signal names the transfer and nothing else. The job runs with no
  person (ADR 0067).
  """

  use Ash.Resource.Change

  alias Ash.Changeset

  @impl true
  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn changeset, transfer ->
      if transfer.state == :sending do
        case Ash.Signals.emit(
               changeset,
               Rescord.Transfers.Signals,
               :transfer_started,
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
