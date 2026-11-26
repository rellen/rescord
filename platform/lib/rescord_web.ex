defmodule RescordWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, components, channels, and so on.

  This can be used in your application as:

      use RescordWeb, :controller
      use RescordWeb, :html

  The definitions below will be executed for every controller,
  component, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define additional modules and import
  those modules here.

  ## The boundary of the web layer

  This module is also the boundary of the web layer (ADR 0009). The web
  layer may use the core's exports and the exports of each Ash domain in
  `deps`. It may not use `:ash` itself: a call such as `Ash.read!/1` does
  not compile. Call a domain's code interface instead, and add the domain to
  `deps` below. To use one module of Ash, such as an error struct, add that
  module to `deps`.
  """

  use Boundary,
    deps: [
      Rescord,
      Rescord.Accounts,
      Rescord.Lists,
      Rescord.Residents,
      Rescord.Locations,
      Rescord.Journal,
      Rescord.Photos,
      Rescord.Tasks,
      Rescord.Inventory,
      Rescord.Transfers,
      Rescord.Export
    ],
    exports: [Endpoint, Telemetry],
    check: [aliases: true, apps: [:ash]]

  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      use Gettext, backend: RescordWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView

      # The text of a field of a form, or nil for a blank one or for a value
      # that is not text, which a forged event can send.
      import Shoddy.Strings, only: [non_blank: 1]

      # A form drawn again from what the browser sent keeps only text.
      import RescordWeb.Input, only: [typed_form: 2, typed_fields: 1]

      unquote(html_helpers())
    end
  end

  @doc """
  For a live widget (ADR 0003): function components, the helpers of
  `shoddy_phoenix` for widgets, and the LiveView functions that act on the
  page's socket from a hook.

  There is no `live_component/0`: a stateful part of a page is a widget.
  """
  def widget do
    quote do
      use Phoenix.Component

      import Phoenix.LiveView,
        only: [
          push_event: 3,
          push_navigate: 2,
          push_patch: 2,
          put_flash: 3,
          stream: 3,
          stream: 4,
          stream_delete: 3,
          stream_insert: 3,
          stream_insert: 4
        ]

      alias RescordWeb.Widget
      alias ShoddyPhoenix.LiveView.Subscriptions
      alias ShoddyPhoenix.LiveView.Widgets

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      # Translation
      use Gettext, backend: RescordWeb.Gettext

      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import RescordWeb.CoreComponents
      # Control flow in templates, for three or more branches
      import ShoddyPhoenix.ControlFlow, only: [choose: 1, switch: 1]

      # Common modules used in templates
      alias Phoenix.LiveView.JS
      alias RescordWeb.Layouts

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: RescordWeb.Endpoint,
        router: RescordWeb.Router,
        statics: RescordWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
