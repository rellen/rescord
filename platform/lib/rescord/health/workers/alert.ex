defmodule Rescord.Health.Workers.Alert do
  @moduledoc """
  Sends the alert of the sanity checks to one root user on one channel
  (`Rescord.Health.Alerts`). A fault that can pass, such as a push service
  that did not answer, tries again, 5 times at most. Unique for an hour, so
  a second run of the checks in that hour sends nothing more.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [
      period: 3_600,
      keys: [:user_id, :channel],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "channel" => channel}}) do
    key = Enum.find(Rescord.Notifications.Channel.keys(), &(Atom.to_string(&1) == channel))

    case key && Rescord.Health.Alerts.deliver(user_id, key) do
      {:retry, reason} -> {:error, reason}
      _sent_or_nothing -> :ok
    end
  end
end
