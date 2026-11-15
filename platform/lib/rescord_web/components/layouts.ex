defmodule RescordWeb.Layouts do
  @moduledoc """
  The layouts of the application.

  `root.html.heex` holds the HTML skeleton. `app/1` holds the landmarks
  that every page shares: a skip link, the site header with its nav, the
  main content and the flash messages. The markup is classless (ADR 0004).
  """
  use RescordWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  @doc """
  Renders the app layout around the content of a page.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_user, :map, default: nil, doc: "the user who is signed in, if any"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#main">{gettext("Skip to content")}</a>

    <header>
      <nav aria-label={gettext("Site")}>
        <a href={~p"/"}><.icon name="mark" /> Rescord</a>
        <ul>
          <li :if={@current_user}>{@current_user.email}</li>
          <li :if={@current_user}>
            <.link href={~p"/sign-out"} method="delete">{gettext("Sign out")}</.link>
          </li>
          <li :if={!@current_user}>
            <a href={~p"/sign-in"}>{gettext("Sign in")}</a>
          </li>
        </ul>
      </nav>
    </header>

    <main id="main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  The two messages about the connection are hidden until LiveView marks a
  client or a server error, and are hidden again when it connects.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          JS.show(to: ".phx-client-error #client-error", display: "flex")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")} <.icon name="arrow-path" spin />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          JS.show(to: ".phx-server-error #server-error", display: "flex")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")} <.icon name="arrow-path" spin />
      </.flash>
    </div>
    """
  end
end
