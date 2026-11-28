defmodule Rescord.Notifications.Changes.Deliver do
  @moduledoc """
  Sends a notification on each channel that its person chose and that the
  server has (`Rescord.Notifications.Channel`). The job of the trigger
  `deliver` runs it, with no person.

  A channel that took it is in `delivered`, and is not sent again. A
  channel that answers `{:retry, reason}` is tried again in a new job, a
  minute later and then longer, 5 times at most; then the notification is
  done, and it stays in the app as each one does.

  The notification of a person who is no member now, or of a comment that
  is gone, sends nothing.
  """

  use Ash.Resource.Change

  alias Rescord.{Accounts, Notifications}
  alias Rescord.Notifications.{Channel, Message}

  @tries 5

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      notification = changeset.data
      tries = notification.tries + 1
      settings = Notifications.settings_for_job()
      pending = pending(notification, settings, changeset.tenant)
      message = message(notification, changeset.tenant)

      results =
        for channel <- pending,
            into: %{},
            do: {channel.key(), channel.deliver(message, notification.user_id, settings)}

      took = for {key, :ok} <- results, do: key
      again? = Enum.any?(results, &match?({_key, {:retry, _reason}}, &1)) and tries < @tries

      changeset
      |> Ash.Changeset.force_change_attribute(:delivered, notification.delivered ++ took)
      |> Ash.Changeset.force_change_attribute(:tries, tries)
      |> then(fn changeset ->
        if again?,
          do: Ash.Changeset.after_action(changeset, &again(&1, &2, tries)),
          else: Ash.Changeset.force_change_attribute(changeset, :delivered_at, DateTime.utc_now())
      end)
    end)
  end

  # The channels of the person for this kind, that the server has, and that
  # did not take the notification yet.
  defp pending(notification, settings, tenant) do
    if Accounts.member_for_job(notification.user_id, tenant) do
      chosen = Notifications.channels_for_job(notification.user_id, notification.kind, tenant)

      for channel <- Channel.all(),
          channel.key() in chosen,
          channel.key() not in notification.delivered,
          channel.ready?(settings),
          do: channel
    else
      []
    end
  end

  defp message(notification, tenant),
    do: Message.for(notification, Accounts.organisation_of(tenant))

  defp again(changeset, notification, tries) do
    AshOban.run_trigger(notification, :deliver,
      tenant: changeset.tenant,
      schedule_in: 60 * tries * tries
    )

    {:ok, notification}
  end
end
