defmodule Rescord.Health.Checks.UsageSends do
  @moduledoc """
  C20 of issue 38: in the mode `send` (ADR 0098), the usage counts of
  yesterday are not sent 3 hours into the day (UTC). The job of the usage
  (`Rescord.Usage.Workers.Send`) sends each full day in the hour after it,
  and tries again each hour. It keeps the counts of 7 days, so a send that
  fails for a week loses days, and `bin/check` says so only after a try.

  The id is that of the settings.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :usage_sends
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Usage counts that are not sent"

  @impl true
  def explain,
    do:
      "The server sends its usage counts, and the counts of yesterday did not go. The page " <>
        "of the usage says what the address answered. The counts of a day go after 7 days."

  @impl true
  def run(%{now: now}) do
    today = DateTime.to_date(now)

    if now.hour < 3 do
      ok()
    else
      """
      select s.id from public.usage_settings s
      where s.mode = 'send' and s.endpoint is not null
        and s.sending_since <= $1::date
        and (s.last_sent_day is null or s.last_sent_day < $1::date)
      """
      |> query([Date.add(today, -1)])
      |> found(:fail)
    end
  end
end
