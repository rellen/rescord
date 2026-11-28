defmodule RescordWeb.DeviceEvents do
  @moduledoc """
  The events of the parts of `RescordWeb.DeviceComponents`, for each page
  that shows them: the subscription that the hook `Push` sends, the end of
  one, the removal of a device, and the start, the new address and the end
  of a topic of ntfy.

  A page calls `handle/4` from its `handle_event/3` with a function that
  reads the page again, and handles each other event itself:

      @device_events DeviceEvents.events()

      def handle_event(event, params, socket) when event in @device_events,
        do: DeviceEvents.handle(event, params, socket, &read/1)

  Each action runs as the person of the page, with no organisation: a
  device and a topic are of the person. The page has the assigns `devices`
  and `ntfy`, which it read as the person, and `problems`. It acts only on
  a device that it read.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Rescord.Notifications

  @events ~w(push-subscribe push-unsubscribe remove-device ntfy-start ntfy-renew ntfy-stop)

  @doc "The events that `handle/4` handles."
  @spec events() :: [String.t()]
  def events, do: @events

  @doc "Handles one of `events/0`, and reads the page again with `read`."
  @spec handle(String.t(), map, Phoenix.LiveView.Socket.t(), (Phoenix.LiveView.Socket.t() ->
                                                                Phoenix.LiveView.Socket.t())) ::
          {:noreply, Phoenix.LiveView.Socket.t()} | {:reply, map, Phoenix.LiveView.Socket.t()}
  def handle(
        "push-subscribe",
        %{"endpoint" => endpoint, "keys" => %{} = keys} = params,
        socket,
        read
      )
      when is_binary(endpoint) do
    fields = %{
      endpoint: endpoint,
      device_key: text(keys["p256dh"]),
      auth: text(keys["auth"]),
      device: device(params["device"])
    }

    case Notifications.subscribe_device(fields, actor: socket.assigns.current_user) do
      {:ok, _device} ->
        {:reply, %{ok: true}, socket |> assign(problems: []) |> read.()}

      {:error, error} ->
        problems = for {_field, words} <- Notifications.problems(error), do: words
        {:reply, %{ok: false}, assign(socket, problems: problems)}
    end
  end

  # The browser ended its subscription: the device goes from the list.
  def handle("push-unsubscribe", %{"endpoint" => endpoint}, socket, read)
      when is_binary(endpoint) do
    case Enum.find(socket.assigns.devices, &(&1.endpoint == endpoint)) do
      nil -> {:reply, %{ok: true}, socket}
      device -> remove(socket, device, read, reply?: true)
    end
  end

  def handle("remove-device", %{"device" => id}, socket, read) when is_binary(id) do
    case Enum.find(socket.assigns.devices, &(&1.id == id)) do
      nil -> {:noreply, socket}
      device -> remove(socket, device, read, reply?: false)
    end
  end

  def handle("ntfy-start", _params, socket, read),
    do: ntfy(socket, read, Notifications.start_ntfy(actor: socket.assigns.current_user))

  def handle("ntfy-renew", _params, %{assigns: %{ntfy: %{} = topic}} = socket, read),
    do: ntfy(socket, read, Notifications.renew_ntfy(topic, actor: socket.assigns.current_user))

  def handle("ntfy-stop", _params, %{assigns: %{ntfy: %{} = topic}} = socket, read),
    do: ntfy(socket, read, Notifications.stop_ntfy(topic, actor: socket.assigns.current_user))

  def handle(_event, _params, socket, _read), do: {:noreply, socket}

  defp remove(socket, device, read, reply?: reply?) do
    result = Notifications.remove_device(device, actor: socket.assigns.current_user)
    socket = read.(socket)

    case {result, reply?} do
      {:ok, true} -> {:reply, %{ok: true}, socket}
      {:ok, false} -> {:noreply, socket}
      {{:error, _error}, true} -> {:reply, %{ok: false}, socket}
      {{:error, _error}, false} -> {:noreply, put_flash(socket, :error, "That did not work.")}
    end
  end

  defp ntfy(socket, read, result) do
    case result do
      {:ok, _topic} -> {:noreply, socket |> assign(problems: []) |> read.()}
      :ok -> {:noreply, socket |> assign(problems: []) |> read.()}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "That did not work.")}
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil

  # The kind of a device, which the hook guessed from the browser. It names
  # one of a short list, and makes no atom.
  @devices ~w(iphone ipad android mac windows linux)
  defp device(name) when name in @devices, do: String.to_existing_atom(name)
  defp device(_name), do: :other
end
