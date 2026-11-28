defmodule RescordWeb.Inbox do
  @moduledoc """
  The number of new notifications of the person, for the link of the site
  header (issue 29). A hook of the live session of an organisation: it
  assigns `inbox`, and counts again when a notification of the
  organisation changes (ADR 0096). The count reads as the person, so a
  change of another person's notification gives the same number.

  Each page of an organisation passes `inbox={@inbox}` to `Layouts.app`.
  """

  alias Rescord.{Changes, Notifications}
  alias ShoddyPhoenix.LiveView
  alias ShoddyPhoenix.LiveView.Subscriptions

  def on_mount(:count, _params, _session, socket) do
    socket =
      socket
      |> Phoenix.Component.assign(:inbox, count(socket))
      |> LiveView.when_connected(fn socket ->
        socket =
          for topic <- Changes.topics(socket.assigns.organisation, Notifications),
              reduce: socket,
              do: (socket -> Subscriptions.subscribe(socket, Changes.pubsub(), topic, __MODULE__))

        LiveView.put_hook(socket, __MODULE__, :handle_info, &handle_info/2)
      end)

    {:cont, socket}
  end

  # The page may listen to the notifications too, so the change goes on.
  defp handle_info(%Changes.Change{domain: Notifications}, socket),
    do: {:cont, Phoenix.Component.assign(socket, :inbox, count(socket))}

  defp handle_info(_message, socket), do: {:cont, socket}

  defp count(socket) do
    Notifications.unread_count(
      actor: socket.assigns.current_user,
      tenant: socket.assigns.organisation
    )
  end
end
