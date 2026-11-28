defmodule Rescord.Health.Workers.Check do
  @moduledoc """
  Runs one check that has a job of its own (ADR 0114,
  `c:Rescord.Health.Check.own_job?/0`), such as the comparison of the store
  each week: `Rescord.Health.run_due/1` and the button of `/root/health`
  start it. One try: the next hour starts it again while it is still due.
  Unique for its check while it waits or runs, so a run of an hour does not
  start a second one.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: :infinity, keys: [:check], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"check" => name}}) do
    case Enum.find(Rescord.Health.Checks.all(), &(Atom.to_string(&1.name()) == name)) do
      nil ->
        :ok

      check ->
        Rescord.Health.run_check(check)
        :ok
    end
  end
end
