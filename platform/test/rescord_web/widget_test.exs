defmodule RescordWeb.WidgetTest do
  # How a live widget behaves on a real LiveView (ADR 0003): two instances on
  # one topic each see a message once, an event reaches only the instance
  # that it names, and an event that names no instance, or that no widget
  # owns, changes nothing. No database.
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint RescordWeb.Endpoint

  defmodule Counter do
    @moduledoc false
    # A widget that counts its "add" events and the bumps on its topic.
    use RescordWeb, :widget
    use ShoddyPhoenix.LiveView.Events, prefix: "counter"

    defstruct [:key, :topic, count: 0]

    def assign_widget(socket, key, topic) do
      socket
      |> Widget.put(%__MODULE__{key: key, topic: topic})
      |> Subscriptions.subscribe(Rescord.PubSub, topic, key)
      |> Widgets.route_events(event_prefix(), &handle_event/3)
      |> ShoddyPhoenix.LiveView.put_hook({__MODULE__, :info}, :handle_info, &handle_info/2)
    end

    defp handle_event("add", %{"widget" => key}, socket) do
      case Widget.fetch(socket, __MODULE__, key) do
        {:ok, state} -> {:noreply, Widget.put(socket, %{state | count: state.count + 1})}
        :error -> {:noreply, socket}
      end
    end

    defp handle_event("add", _params, socket), do: {:noreply, socket}

    defp handle_info({:bump, topic}, socket),
      do: {:halt, Widget.update_each(socket, __MODULE__, &bump(&1, topic))}

    defp handle_info(_message, socket), do: {:cont, socket}

    defp bump(%{topic: topic} = state, topic), do: %{state | count: state.count + 1}
    defp bump(state, _topic), do: state

    attr :state, __MODULE__, required: true

    def render(assigns) do
      ~H"""
      <section id={"counter-#{@state.key}"}>
        <output>{@state.count}</output>
        <button type="button" phx-click={event("add")} phx-value-widget={@state.key}>Add</button>
      </section>
      """
    end
  end

  defmodule Page do
    @moduledoc false
    use RescordWeb, :live_view

    alias RescordWeb.WidgetTest.Counter

    @impl true
    def mount(_params, %{"topic" => topic, "other" => other}, socket) do
      {:ok,
       socket
       |> Counter.assign_widget(:left, topic)
       |> Counter.assign_widget(:right, topic)
       |> Counter.assign_widget(:other, other)}
    end

    # The widgets' hooks see each message first and pass on the others.
    @impl true
    def handle_info(_message, socket), do: {:noreply, socket}

    # The widgets own their events, so an event that reaches the page is unknown.
    @impl true
    def handle_event(_event, _params, socket), do: {:noreply, socket}

    @impl true
    def render(assigns) do
      ~H"""
      <Counter.render state={@left} />
      <Counter.render state={@right} />
      <Counter.render state={@other} />
      """
    end
  end

  setup do
    id = System.unique_integer([:positive])
    session = %{"topic" => "counters:#{id}", "other" => "counters:#{id}:other"}
    {:ok, view, _html} = live_isolated(build_conn(), Page, session: session)

    %{view: view, topic: session["topic"]}
  end

  defp count(view, key) do
    view
    |> element("#counter-#{key} output")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
  end

  test "two instances on one topic each see a message once", %{view: view, topic: topic} do
    Phoenix.PubSub.broadcast(Rescord.PubSub, topic, {:bump, topic})
    Phoenix.PubSub.broadcast(Rescord.PubSub, topic, {:bump, topic})

    assert count(view, :left) == "2"
    assert count(view, :right) == "2"
    assert count(view, :other) == "0"
  end

  test "an event reaches only the instance that it names", %{view: view} do
    view |> element("#counter-left button") |> render_click()

    assert count(view, :left) == "1"
    assert count(view, :right) == "0"
  end

  test "an event that names no instance of the widget changes nothing", %{view: view} do
    render_click(view, "counter:add", %{"widget" => "missing"})
    render_click(view, "counter:add", %{"widget" => "flash"})
    render_click(view, "counter:add", %{"widget" => %{"not" => "text"}})
    render_click(view, "counter:add", %{})

    assert Enum.map([:left, :right, :other], &count(view, &1)) == ["0", "0", "0"]
  end

  test "an event that no widget owns reaches the page, which ignores it", %{view: view} do
    render_click(view, "unknown", %{"widget" => "left"})

    assert count(view, :left) == "0"
  end
end
