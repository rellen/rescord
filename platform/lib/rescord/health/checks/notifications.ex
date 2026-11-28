defmodule Rescord.Health.Checks.Notifications do
  @moduledoc """
  C21 of issue 38: notifications that the channels did not take, and
  notifications that the prune forgot.

    * A notification with no `delivered_at` 2 hours after it came. Its job
      tries 5 times within half an hour (`Rescord.Notifications.Changes.Deliver`),
      and the trigger has no scheduler, so a job that is lost never runs
      again.
    * A notification older than the prune keeps (30 days after it was
      read, 90 days after it came), with a day more: the prune of each
      night logs the fault of an organisation and still ends well.

  The ids are those of the notifications.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :notifications
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Notifications that did not leave, or that stay too long"

  @impl true
  def explain,
    do:
      "A notification did not go to the devices and the topics after 2 hours, or is older " <>
        "than Rescord keeps one. Look in the log for the job of the notifications, and for " <>
        "the prune of each night."

  @impl true
  def run(%{now: now} = context) do
    """
    select n.id from #{table(context, "notifications")} n
    where (n.delivered_at is null and n.inserted_at < $1::timestamp - interval '2 hours')
      or n.read_at < $1::timestamp - interval '31 days'
      or n.inserted_at < $1::timestamp - interval '91 days'
    """
    |> query([DateTime.to_naive(now)])
    |> found(:fail)
  end
end
