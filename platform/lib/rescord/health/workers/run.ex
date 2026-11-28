defmodule Rescord.Health.Workers.Run do
  @moduledoc """
  Runs the checks that are due (ADR 0114), each hour, from the crontab of
  Oban. One try: the next hour runs again what is still due. Unique for
  the hour, so a second node or a start by hand does not run the checks
  twice.
  """

  use Oban.Worker,
    queue: :health,
    max_attempts: 1,
    unique: [period: 3_000, states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(_job) do
    Rescord.Health.run_due()
    :ok
  end
end
