defmodule Rescord.Transfers.Signals do
  @moduledoc """
  What the transfers tell their listeners (ADR 0100).

    * `:transfer_started` - a transfer to a partner on this server was
      written with the state `sending`, and its files are still in the
      store of the refuge that sent it. `Rescord.Transfers.Transfer`
      listens in a job, which copies the files after the commit, and
      again after a fault.

  No other domain listens, so the domain does not export this module.
  `mix ash.signals` prints what emits each signal and what listens to it.
  """

  use Ash.Signals

  signals do
    signal :transfer_started do
      description "A transfer was written, and its files wait to be copied"
      argument :transfer_id, :uuid, allow_nil?: false
    end
  end
end
