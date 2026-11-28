defmodule RescordWeb.Layouts do
  @moduledoc """
  The layouts of the application.

  `root.html.heex` holds the HTML skeleton. `app/1` holds the landmarks
  that every page shares: a skip link, the site header with its nav, the
  main content, the site footer and the flash messages. `plain/1` holds
  the same landmarks for a page that knows no person, such as the page of
  an error. The markup is classless (ADR 0004).
  """
  use RescordWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  # The version of Rescord, which the footer shows to a person who is
  # signed in.
  @version Mix.Project.config()[:version]

  @doc """
  The title of a document: the title of the page, or the words of an error
  page (ADR 0090). The root layout adds the name of the site after it.
  """
  def title(assigns) do
    assigns[:page_title] || error_title(assigns[:status] || status_of(assigns[:conn]))
  end

  defp status_of(%Plug.Conn{status: status}), do: status
  defp status_of(_other), do: nil

  defp error_title(status) when is_integer(status) and status >= 400,
    do: RescordWeb.ErrorHTML.words(status).title

  defp error_title(_status), do: nil

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

  attr :inbox, :integer,
    default: nil,
    doc: "the number of new notifications of the person, from `RescordWeb.Inbox`"

  attr :section, :atom,
    default: nil,
    values:
      [nil, :home, :tasks, :residents, :groups, :housing, :inventory, :expenses, :tools, :reports] ++
        [:lists, :members, :settings, :ruby, :notifications, :root],
    doc: "the part of the site that the page is in, which the site nav marks"

  attr :rest, :global, doc: "the attributes of `<main>`, such as the `data-` attribute of a page"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#main">{gettext("Skip to content")}</a>

    <header>
      <nav aria-label={gettext("Site")}>
        <a href={~p"/"}><.icon name="mark" /> Rescord</a>
        <a :if={!@current_user} href={~p"/sign-in"}><.icon name="door-in" /> {gettext("Sign in")}</a>
        <.inbox_link
          :if={@current_user && @organisation}
          organisation={@organisation}
          count={@inbox || 0}
          current={@section == :notifications}
        />
        <button :if={@current_user} type="button" popovertarget="site-menu">
          <.icon name="bars" /> {gettext("Menu")}
        </button>
        <div :if={@current_user} id="site-menu" popover>
          <ul :if={@organisation}>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}"}
                aria-current={current(@section, :home)}
              >
                <.icon name={Icons.section(:home)} /> {@organisation.name}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/tasks"}
                aria-current={current(@section, :tasks)}
              >
                <.icon name={Icons.section(:tasks)} /> {gettext("Tasks")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/residents"}
                aria-current={current(@section, :residents)}
              >
                <.icon name={Icons.section(:residents)} /> {gettext("Residents")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/groups"}
                aria-current={current(@section, :groups)}
              >
                <.icon name={Icons.section(:groups)} /> {gettext("Groups")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/housing"}
                aria-current={current(@section, :housing)}
              >
                <.icon name={Icons.section(:housing)} /> {gettext("Housing")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/inventory"}
                aria-current={current(@section, :inventory)}
              >
                <.icon name={Icons.section(:inventory)} /> {gettext("Inventory")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/expenses"}
                aria-current={current(@section, :expenses)}
              >
                <.icon name={Icons.section(:expenses)} /> {gettext("Expenses")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/tools"}
                aria-current={current(@section, :tools)}
              >
                <.icon name={Icons.section(:tools)} /> {gettext("Tools")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/reports"}
                aria-current={current(@section, :reports)}
              >
                <.icon name={Icons.section(:reports)} /> {gettext("Reports")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/lists"}
                aria-current={current(@section, :lists)}
              >
                <.icon name={Icons.section(:lists)} /> {gettext("Lists")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/members"}
                aria-current={current(@section, :members)}
              >
                <.icon name={Icons.section(:members)} /> {gettext("Members")}
              </.link>
            </li>
            <li>
              <.link
                navigate={~p"/o/#{@organisation.short_name}/settings"}
                aria-current={current(@section, :settings)}
              >
                <.icon name={Icons.section(:settings)} /> {gettext("Settings")}
              </.link>
            </li>
          </ul>
          <ul>
            <li :if={@current_user.root?}>
              <.link navigate={~p"/root"} aria-current={current(@section, :root)}>
                <.icon name={Icons.section(:root)} /> {gettext("Root")}
              </.link>
            </li>
            <li>
              <span><.icon name="user-circle" /> {@current_user.email}</span>
            </li>
            <li>
              <.link href={~p"/sign-out"} method="delete">
                <.icon name="door-out" /> {gettext("Sign out")}
              </.link>
            </li>
          </ul>
        </div>
      </nav>
    </header>

    <main id="main" tabindex="-1" {@rest}>
      {render_slot(@inner_block)}
    </main>

    <.site_footer version={@current_user && version()} />

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the landmarks around a page that knows no person: the skip link,
  the site header with the name of the site alone, the main content and
  the site footer. The page of an error uses it, because an error can come
  before Rescord knows who asks, and must not depend on what failed.

  ## Examples

      <Layouts.plain>
        <h1>Rescord has no page at this address</h1>
      </Layouts.plain>

  """
  slot :inner_block, required: true

  def plain(assigns) do
    ~H"""
    <a href="#main">{gettext("Skip to content")}</a>

    <header>
      <nav aria-label={gettext("Site")}>
        <a href={~p"/"}><.icon name="mark" /> Rescord</a>
      </nav>
    </header>

    <main id="main" tabindex="-1">
      {render_slot(@inner_block)}
    </main>

    <.site_footer />
    """
  end

  @doc """
  Renders the site footer: the landmark `contentinfo` of each page, with
  the links to what Rescord is and how it is built (ADR 0090).

  A person who is signed in also sees the version. A visitor does not: the
  version of a server is of use to a person who looks for a known fault.
  """
  attr :version, :string,
    default: nil,
    doc: "the version of Rescord, for a person who is signed in"

  def site_footer(assigns) do
    ~H"""
    <footer>
      <nav aria-label={gettext("About Rescord")}>
        <ul>
          <li><a href={~p"/colophon"}>{gettext("Colophon")}</a></li>
          <li><a href={~p"/colophon#accessibility"}>{gettext("Accessibility")}</a></li>
          <li><a href="https://github.com/rellen/rescord">{gettext("Source code")}</a></li>
        </ul>
      </nav>
      <p :if={@version}>Rescord {@version}</p>
    </footer>
    """
  end

  @doc """
  The link of the site bar to the notifications of the person (issue 29),
  with the number of new ones. It is in the bar on each screen, so a phone
  shows it without the menu; there the words are for a screen reader only.
  The number is a shape and a number, never a colour alone.
  """
  attr :organisation, :map, required: true
  attr :count, :integer, required: true
  attr :current, :boolean, default: false

  def inbox_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/o/#{@organisation.short_name}/notifications"}
      data-inbox
      aria-current={@current && "true"}
    >
      <.icon name="bell" /><span>{gettext("Notifications")}</span>
      <data :if={@count > 0} value={@count}>{@count}<span>{gettext("new")}</span></data>
    </.link>
    """
  end

  @doc "The version of Rescord that runs."
  def version, do: @version

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
