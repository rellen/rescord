defmodule Rescord.Transfers.Signals do
  @moduledoc """
  What the transfers tell their listeners (ADR 0100).

    * `:transfer_started` - a transfer to a partner on this server was
      written with the state `sending`, and its files are still in the
      store of the refuge that sent it. `Rescord.Transfers.Transfer`
      listens in a job, which copies the files after the commit, and
      again after a fault.
    * `:transfer_imported` - a transfer file from a partner on another
      server was read, and its files are in the store of this refuge, as
      the other server sent them (issue 37). `Rescord.Transfers.Transfer`
      listens in a job, which cleans its photos and scans its PDFs after
      the commit, and holds the files until then.

  No other domain listens, so the domain does not export this module.
  `mix ash.signals` prints what emits each signal and what listens to it.
  """

  use Ash.Signals

  signals do
    signal :transfer_started do
      description "A transfer was written, and its files wait to be copied"
      argument :transfer_id, :uuid, allow_nil?: false
    end

    signal :transfer_imported do
      description "A transfer file was read, and its files wait to be checked"
      argument :transfer_id, :uuid, allow_nil?: false
    end
  end
end
