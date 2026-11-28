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
  attr :organisation, :map, default: nil, doc: "the organisation of the page, if it has one"

  attr :section, :atom,
    default: nil,
    values:
      [nil, :home, :tasks, :residents, :groups, :housing, :inventory, :expenses, :tools, :reports] ++
        [:lists, :members, :settings, :root],
    doc: "the part of the site that the page is in, which the site nav marks"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#main">{gettext("Skip to content")}</a>

    <header>
      <nav aria-label={gettext("Site")}>
        <a href={~p"/"}><.icon name="mark" /> Rescord</a>
        <a :if={!@current_user} href={~p"/sign-in"}>{gettext("Sign in")}</a>
        <button :if={@current_user} type="button" popovertarget="site-menu">
          <.icon name="bars" /> {gettext("Menu")}
        </button>
        <div :if={@current_user} id="site-menu" popover>
          <ul :if={@organisation}>
            <li>
              <a href={~p"/o/#{@organisation.short_name}"} aria-current={current(@section, :home)}>
                {@organisation.name}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/tasks"}
                aria-current={current(@section, :tasks)}
              >
                {gettext("Tasks")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/residents"}
                aria-current={current(@section, :residents)}
              >
                {gettext("Residents")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/groups"}
                aria-current={current(@section, :groups)}
              >
                {gettext("Groups")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/housing"}
                aria-current={current(@section, :housing)}
              >
                {gettext("Housing")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/inventory"}
                aria-current={current(@section, :inventory)}
              >
                {gettext("Inventory")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/expenses"}
                aria-current={current(@section, :expenses)}
              >
                {gettext("Expenses")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/tools"}
                aria-current={current(@section, :tools)}
              >
                {gettext("Tools")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/reports"}
                aria-current={current(@section, :reports)}
              >
                {gettext("Reports")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/lists"}
                aria-current={current(@section, :lists)}
              >
                {gettext("Lists")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/members"}
                aria-current={current(@section, :members)}
              >
                {gettext("Members")}
              </a>
            </li>
            <li>
              <a
                href={~p"/o/#{@organisation.short_name}/settings"}
                aria-current={current(@section, :settings)}
              >
                {gettext("Settings")}
              </a>
            </li>
          </ul>
          <ul>
            <li :if={@current_user.root?}>
              <a href={~p"/root"} aria-current={current(@section, :root)}>{gettext("Root")}</a>
            </li>
            <li><span title={@current_user.email}>{@current_user.email}</span></li>
            <li>
              <.link href={~p"/sign-out"} method="delete">{gettext("Sign out")}</.link>
            </li>
          </ul>
        </div>
      </nav>
    </header>

    <main id="main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # The link of the part that the page is in says so (ADR 0061). The page
  # can be a page below that link, so the value is `true` and not `page`.
  defp current(section, section), do: "true"
  defp current(_section, _link), do: nil

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
