defmodule RescordWeb.Widget do
  @moduledoc """
  Helpers for live widgets (ADR 0003).

  A live widget is a stateful part of a page that lives in the page's
  LiveView process. It follows the guide "Build a widget with lifecycle
  hooks" of `shoddy_phoenix`, which follows Curiosum's "Hooking up with
  LiveView: stateful widgets with function components":

    * its state is a struct with a `:key` field, stored in the page's
      assigns under that key, so a page can hold several instances;
    * `assign_widget/2,3` puts the state, subscribes with
      `ShoddyPhoenix.LiveView.Subscriptions`, routes the widget's events with
      `ShoddyPhoenix.LiveView.Widgets.route_events/3`, and attaches its
      `:handle_info` hook with `ShoddyPhoenix.LiveView.put_hook/4`;
    * its events are written with `event/1` of
      `ShoddyPhoenix.LiveView.Events`, so a misspelt event name fails the
      compile, and they name their instance in a `"widget"` parameter;
    * `render/1` is a pure function component that takes `state`.

  A widget module starts with:

      use RescordWeb, :widget
      use ShoddyPhoenix.LiveView.Events, prefix: "chat"

  This module holds the bookkeeping that every widget repeats: find the
  instance an event names, store an instance, and update each instance.
  """

  alias Phoenix.LiveView.Socket
  alias ShoddyPhoenix.LiveView.Widgets

  @doc """
  The instance of `module` whose key, as text, is `key`.

  A client chooses `key`, so it is compared as text and never turned into
  an atom. Any value that names no instance of `module` gives `:error`.
  """
  @spec fetch(Socket.t(), module(), term()) :: {:ok, struct()} | :error
  def fetch(%Socket{} = socket, module, key) do
    with {:ok, {_key, state}} <- Widgets.fetch_instance(socket, module, key), do: {:ok, state}
  end

  @doc "Stores an instance's state under its key."
  @spec put(Socket.t(), struct()) :: Socket.t()
  def put(%Socket{} = socket, %{key: key} = state),
    do: Phoenix.Component.assign(socket, key, state)

  @doc "Every instance of `module` in the assigns."
  @spec instances(Socket.t(), module()) :: [struct()]
  def instances(%Socket{assigns: assigns}, module) do
    for {_key, %{__struct__: ^module} = state} <- assigns, do: state
  end

  @doc "Replaces each instance of `module` with `fun.(state)`."
  @spec update_each(Socket.t(), module(), (struct() -> struct())) :: Socket.t()
  def update_each(%Socket{} = socket, module, fun) do
    socket
    |> instances(module)
    |> Enum.reduce(socket, fn state, socket -> put(socket, fun.(state)) end)
  end
end
