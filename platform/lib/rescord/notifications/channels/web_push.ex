defmodule Rescord.Notifications.Channels.WebPush do
  @moduledoc """
  The channel of Web Push (issue 29, ADR 0106): a message to each device of
  the person (`Rescord.Notifications.PushSubscription`), encrypted for the
  device (RFC 8291) and signed with the key of the server (RFC 8292).

  A push service answers 201 for a message that it took, and 404 or 410
  for a device that is gone, which the channel then forgets. 429, a 5xx and
  a fault of the network try again; another answer drops the message for
  that device, with a warning in the log.
  """

  @behaviour Rescord.Notifications.Channel

  require Ash.Query
  require Logger

  alias Rescord.Notifications.{Channel, Message, PushSubscription, Secrets, Settings, WebPush}

  # A message that waits more than a day at the push service is no news.
  @ttl 24 * 60 * 60

  @impl true
  def key, do: :web_push

  @impl true
  def ready?(%Settings{push_on: true, vapid_public_key: key, contact: contact})
      when is_binary(key) and is_binary(contact),
      do: true

  def ready?(_settings), do: false

  @impl true
  def set_up?(user_id), do: subscriptions(user_id) != []

  @impl true
  def deliver(%Message{} = message, user_id, %Settings{} = settings) do
    with {:ok, keys} <- keys(settings) do
      user_id
      |> subscriptions()
      |> Enum.map(&send_to(&1, message, keys, settings.contact))
      |> Enum.find(:ok, &match?({:retry, _reason}, &1))
    end
  end

  defp subscriptions(user_id) do
    PushSubscription
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read!(authorize?: false)
  end

  defp send_to(subscription, message, keys, contact) do
    with {:ok, %{auth: auth}} when is_binary(auth) <- Secrets.open(subscription, :auth),
         {:ok, auth} <- WebPush.decode(auth),
         {:ok, device_key} <- WebPush.decode(subscription.device_key),
         true <- WebPush.allowed_endpoint?(subscription.endpoint) do
      body = WebPush.encrypt(Message.json(message), device_key, auth)

      [
        url: subscription.endpoint,
        body: body,
        headers: [
          {"authorization",
           WebPush.vapid(subscription.endpoint, keys, contact, DateTime.utc_now())},
          {"content-encoding", "aes128gcm"},
          {"content-type", "application/octet-stream"},
          {"ttl", Integer.to_string(@ttl)},
          {"urgency", "normal"}
        ]
      ]
      |> Keyword.merge(Channel.request_options())
      |> Req.post()
      |> answer(subscription)
    else
      # A device that this server cannot write to: ask the person again.
      _sealed_or_wrong -> forget(subscription)
    end
  end

  defp answer({:ok, %Req.Response{status: status}}, subscription) when status in 200..299 do
    Ash.update!(subscription, %{}, action: :note_sent, authorize?: false)
    :ok
  end

  defp answer({:ok, %Req.Response{status: status}}, subscription) when status in [404, 410],
    do: forget(subscription)

  defp answer({:ok, %Req.Response{status: status}}, _subscription)
       when status == 429 or status >= 500,
       do: {:retry, :push_service}

  defp answer({:ok, %Req.Response{status: status}}, _subscription) do
    Logger.warning("A push service refused a message with the status #{status}")
    :ok
  end

  defp answer({:error, _exception}, _subscription), do: {:retry, :unreachable}

  defp forget(subscription) do
    Ash.destroy!(subscription, action: :forget, authorize?: false)
    :ok
  end

  defp keys(%Settings{} = settings) do
    with {:ok, %{vapid_private_key: private}} when is_binary(private) <-
           Secrets.open(settings, :vapid_private_key),
         {:ok, private} <- WebPush.decode(private),
         {:ok, public} <- WebPush.decode(settings.vapid_public_key) do
      {:ok, %{public: public, private: private}}
    else
      _sealed -> {:retry, :sealed}
    end
  end
end
