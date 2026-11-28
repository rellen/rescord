defmodule Rescord.Usage.Workers.Send do
  @moduledoc """
  The work of each hour for the usage counts (ADR 0098): it deletes the
  counts that are too old, and in the mode `send` it sends the full days
  that are not sent yet (`Rescord.Usage.send_due/1`). The cron of Oban
  starts it.

  It tries one time: the next hour is the next try, and a day that the
  address did not take stays for it.
  """

  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 3_000]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Rescord.Usage.send_due(Date.utc_today())
  end
end
