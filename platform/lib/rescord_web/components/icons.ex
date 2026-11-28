defmodule RescordWeb.Icons do
  @moduledoc """
  Our own icons, drawn by hand (ADR 0004, ADR 0102).

  Each icon is a drawing on a square of 24 units, inside the square from 2
  to 22: one line of 2 units with round ends and joins, no fill, and the
  colour of the words (`currentColor`). A dot is a line of no length
  (`h.01`). An icon is 1em, as big as the words beside it.

  An icon is never alone. It is `aria-hidden`, and the words beside it, or
  the `aria-label` of its button, say what it means. A name says the shape,
  not the meaning: the functions below say which shape a meaning takes, so
  that one place of the site has one shape on each page.

  To add an icon, add its drawing to `@drawings` and a line to the example
  `icons.html.heex` of the catalogue (ADR 0095).
  """

  use Phoenix.Component

  @drawings %{
    "adjustments" =>
      ~S|<path d="M4 7h8.5M16.5 7H20M4 17h3.5M11.5 17H20"/><circle cx="14.5" cy="7" r="2"/><circle cx="9.5" cy="17" r="2"/>|,
    "archive-box" =>
      ~S|<rect x="3" y="4" width="18" height="4.5" rx="1"/><path d="M4.5 8.5V19a1.5 1.5 0 0 0 1.5 1.5h12a1.5 1.5 0 0 0 1.5-1.5V8.5M10 12.5h4"/>|,
    "arrow-down-tray" =>
      ~S|<path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>|,
    "arrow-down" => ~S|<path d="M12 5v14M6 13l6 6 6-6"/>|,
    "arrow-path" => ~S|<path d="M20 12a8 8 0 1 1-2.34-5.66"/><path d="M20 4v4h-4"/>|,
    "arrow-right" => ~S|<path d="M4.5 12h15M13.5 6l6 6-6 6"/>|,
    "arrow-top-right-on-square" =>
      ~S|<path d="M13.5 4.5h6v6M19.5 4.5 11 13M17 13.5V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2h4.5"/>|,
    "arrow-turn-down-right" => ~S|<path d="M5 4v7a3 3 0 0 0 3 3h11"/><path d="M15 10l4 4-4 4"/>|,
    "arrow-up-tray" =>
      ~S|<path d="M12 15.5V4.5M7.5 9 12 4.5 16.5 9M4 15v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>|,
    "arrow-up" => ~S|<path d="M12 19V5M6 11l6-6 6 6"/>|,
    "arrow-uturn-left" =>
      ~S|<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>|,
    "arrows-right-left" => ~S|<path d="M4 8h15.5M15.5 4l4 4-4 4M20 16H4.5M8.5 12l-4 4 4 4"/>|,
    "banknotes" =>
      ~S|<rect x="2.5" y="6" width="19" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12h.01M18 12h.01"/>|,
    "bars" => ~S|<path d="M4 7h16M4 12h16M4 17h16"/>|,
    "bell" =>
      ~S|<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z"/><path d="M10 20a2 2 0 0 0 4 0"/>|,
    "book-open" =>
      ~S|<path d="M12 6.5C10.5 5 8 4.5 3.5 4.5v14c4.5 0 7 .5 8.5 2 1.5-1.5 4-2 8.5-2v-14c-4.5 0-7 .5-8.5 2zM12 6.5v14"/>|,
    "building" =>
      ~S|<path d="M4 20.5V5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v15.5M15 9.5h4a1 1 0 0 1 1 1v10M2.5 20.5h19M8 8h3M8 12h3M8 16h3"/>|,
    "calculator" =>
      ~S|<rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="6" width="8" height="3.5" rx=".5"/><path d="M8.5 13.5h.01M12 13.5h.01M15.5 13.5h.01M8.5 17.5h.01M12 17.5h.01M15.5 17.5h.01"/>|,
    "calendar" =>
      ~S|<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>|,
    "chart-bar" => ~S|<path d="M4 20.5h16M7 16.5V12M12 16.5V6M17 16.5V9"/>|,
    "chart-line" => ~S|<path d="M4 4v16h16"/><path d="M7.5 15l3.5-4 3 2.5 5-6"/>|,
    "check" => ~S|<path d="M5 12.5l4.5 4.5L19 7.5"/>|,
    "chevron-down" => ~S|<path d="M6 9l6 6 6-6"/>|,
    "chevron-left" => ~S|<path d="M15 6l-6 6 6 6"/>|,
    "chevron-right" => ~S|<path d="M9 6l6 6-6 6"/>|,
    "chevron-up-down" => ~S|<path d="M8 9.5l4-4 4 4M8 14.5l4 4 4-4"/>|,
    "chevron-up" => ~S|<path d="M6 15l6-6 6 6"/>|,
    "clipboard-check" =>
      ~S|<rect x="5" y="4.5" width="14" height="16.5" rx="2"/><rect x="9" y="3" width="6" height="3" rx="1"/><path d="M8.5 13.5l2.5 2.5 4.5-5"/>|,
    "clock" => ~S|<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>|,
    "document-chart" =>
      ~S|<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 17.5v-3M12 17.5v-5.5M15 17.5v-2"/>|,
    "document-duplicate" =>
      ~S|<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>|,
    "document-text" =>
      ~S|<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 12.5h6M9 16.5h6"/>|,
    "door-in" => ~S|<path d="M14 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4M3.5 12H14M10 8l4 4-4 4"/>|,
    "door-out" =>
      ~S|<path d="M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4M9.5 12h11M16.5 8l4 4-4 4"/>|,
    "envelope" =>
      ~S|<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3.5 6.5 12 13l8.5-6.5"/>|,
    "equals" => ~S|<path d="M6 9h12M6 15h12"/>|,
    "exclamation-circle" =>
      ~S|<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5h.01"/>|,
    "exclamation-triangle" => ~S|<path d="M12 4l9 16H3z"/><path d="M12 10v4M12 17h.01"/>|,
    "eye" =>
      ~S|<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>|,
    "flag" => ~S|<path d="M5.5 21V4M5.5 4.5h12l-2.5 4 2.5 4h-12"/>|,
    "forward" => ~S|<path d="M5 6l6 6-6 6M13 6l6 6-6 6"/>|,
    "funnel" => ~S|<path d="M4 5h16l-6 7.5V19l-4 1.5v-8z"/>|,
    "gem" => ~S|<path d="M7 4h10l4 5-9 11L3 9z"/><path d="M3 9h18M9.5 4 8 9l4 11 4-11-1.5-5"/>|,
    "globe" =>
      ~S|<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3z"/>|,
    "hashtag" => ~S|<path d="M10 4 8 20M16 4l-2 16M4.5 9h15.5M4 15h15.5"/>|,
    "identification" =>
      ~S|<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="11" r="2"/><path d="M5.5 16a3 3 0 0 1 6 0M14 10h4M14 13.5h4"/>|,
    "information-circle" => ~S|<circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.5h.01"/>|,
    "kennel" =>
      ~S|<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10.5h14V10"/><path d="M9.5 20.5V17a2.5 2.5 0 0 1 5 0v3.5"/>|,
    "key" =>
      ~S|<circle cx="8" cy="15.5" r="4.5"/><path d="M11.2 12.3 20 3.5M16.5 7l3 3M14 9.5l2 2"/>|,
    "link" =>
      ~S|<path d="M10 14a4 4 0 0 0 5.66 0l3-3A4 4 0 0 0 13 5.34l-1 1"/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3A4 4 0 0 0 11 18.66l1-1"/>|,
    "list-bullet" => ~S|<path d="M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"/>|,
    "magnifying-glass" => ~S|<circle cx="10.5" cy="10.5" r="6.5"/><path d="M15.5 15.5 20 20"/>|,
    "map-pin" =>
      ~S|<path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.5"/>|,
    "mark" => ~S|<rect x="3" y="3" width="18" height="18" rx="5"/><path d="M12 8v8M8 12h8"/>|,
    "minus-circle" => ~S|<circle cx="12" cy="12" r="9"/><path d="M8 12h8"/>|,
    "minus" => ~S|<path d="M5 12h14"/>|,
    "no-symbol" => ~S|<circle cx="12" cy="12" r="9"/><path d="M5.6 5.6l12.8 12.8"/>|,
    "paper-airplane" => ~S|<path d="M3.5 4.5 21 12 3.5 19.5 6 12z"/><path d="M6 12h7"/>|,
    "paper-clip" =>
      ~S|<path d="M20 11.5l-8.2 8.2a5 5 0 0 1-7-7l8.6-8.6a3.4 3.4 0 0 1 4.8 4.8l-8.5 8.5a1.8 1.8 0 0 1-2.6-2.6l7.8-7.8"/>|,
    "pause" => ~S|<path d="M9 5.5v13M15 5.5v13"/>|,
    "paws" =>
      ~S|<circle cx="7" cy="18" r="2.2"/><circle cx="17" cy="9" r="2.2"/><path d="M3.6 13.8h.01M7 12.4h.01M10.4 13.8h.01M13.6 4.8h.01M17 3.4h.01M20.4 4.8h.01"/>|,
    "paw" =>
      ~S|<path d="M12 12.5c-2.6 0-5.5 3.3-5.5 5.7 0 1.5 1.1 2.3 2.5 2.3 1.2 0 2-.7 3-.7s1.8.7 3 .7c1.4 0 2.5-.8 2.5-2.3 0-2.4-2.9-5.7-5.5-5.7z"/><path d="M9 4.5c1 0 1.6 1.2 1.6 2.6S10 9.7 9 9.7 7.4 8.5 7.4 7.1 8 4.5 9 4.5zM15 4.5c1 0 1.6 1.2 1.6 2.6s-.6 2.6-1.6 2.6-1.6-1.2-1.6-2.6.6-2.6 1.6-2.6zM4.6 9.6c.9-.3 1.9.5 2.2 1.6s0 2.3-.9 2.6-1.9-.5-2.2-1.6 0-2.3.9-2.6zM19.4 9.6c.9.3 1.2 1.5.9 2.6s-1.3 1.9-2.2 1.6-1.2-1.5-.9-2.6 1.3-1.9 2.2-1.6z"/>|,
    "pencil" => ~S|<path d="M15.5 4.5l4 4L9 19l-5 1 1-5z"/><path d="M13.5 6.5l4 4"/>|,
    "photo" =>
      ~S|<rect x="3" y="4.5" width="18" height="15" rx="2"/><path d="M3.5 17l5-5 4 4 2.5-2.5 5.5 5.5M15.5 9h.01"/>|,
    "pill-bottle" =>
      ~S|<rect x="5.5" y="3" width="13" height="4" rx="1"/><path d="M6.5 7v12a2 2 0 0 0 2 2h7a2 2 0 0 0 2-2V7M9.5 13.5h5M12 11v5"/>|,
    "pill" =>
      ~S|<rect x="2.5" y="8.5" width="19" height="7" rx="3.5" transform="rotate(-45 12 12)"/><path d="M9.5 9.5l5 5"/>|,
    "play" => ~S|<path d="M7.5 5v14l11-7z"/>|,
    "plus" => ~S|<path d="M12 5v14M5 12h14"/>|,
    "printer" =>
      ~S|<path d="M7 9V3.5h10V9M7 17H5.5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H17"/><path d="M7 14h10v6.5H7z"/>|,
    "pulse" => ~S|<path d="M3 12h4l2.5-6 4 12 2.5-6h5"/>|,
    "receipt" =>
      ~S|<path d="M6 3h12v18l-2-1.5-2 1.5-2-1.5-2 1.5-2-1.5L6 21z"/><path d="M9 7.5h6M9 11.5h6M9 15.5h3"/>|,
    "repeat" =>
      ~S|<path d="M4 11V9.5a3 3 0 0 1 3-3h12.5M16.5 3.5l3 3-3 3M20 13v1.5a3 3 0 0 1-3 3H4.5M7.5 20.5l-3-3 3-3"/>|,
    "rss" =>
      ~S|<path d="M5 4.5A14.5 14.5 0 0 1 19.5 19M5 10.5a8.5 8.5 0 0 1 8.5 8.5M5.5 18.5h.01"/>|,
    "scale" =>
      ~S|<path d="M7 4.5h10M12 4.5V7"/><rect x="4" y="7" width="16" height="13.5" rx="2.5"/><path d="M9 15a3 3 0 0 1 6 0M12 15l1.5-2"/>|,
    "scissors" =>
      ~S|<circle cx="6.5" cy="17.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/><path d="M8.3 15.7 18 4M15.7 15.7 6 4"/>|,
    "shield" => ~S|<path d="M12 3l7.5 3v5.5c0 4.6-3.2 8-7.5 9.5-4.3-1.5-7.5-4.9-7.5-9.5V6z"/>|,
    "star" =>
      ~S|<path d="M12 3.5l2.6 5.3 5.9.9-4.25 4.1 1 5.8L12 16.9l-5.25 2.7 1-5.8L3.5 9.7l5.9-.9z"/>|,
    "stop" => ~S|<rect x="7" y="7" width="10" height="10" rx="1.5"/>|,
    "stethoscope" =>
      ~S|<path d="M6 3.5H5v5a4 4 0 0 0 8 0v-5h-1M9 12.5V15a5 5 0 0 0 10 0v-2.5"/><circle cx="19" cy="10.5" r="2"/>|,
    "syringe" =>
      ~S|<path d="M14 6l4 4-8.5 8.5-4-4z"/><path d="M7.5 16.5 3.5 20.5M16 8l3.5-3.5M18 3l3 3M10.5 9.5 12 11M8.5 11.5 10 13"/>|,
    "timeline" =>
      ~S|<circle cx="6" cy="6" r="2"/><circle cx="6" cy="18" r="2"/><path d="M6 8v8M11 6h9M11 12h9M11 18h9"/>|,
    "trash" => ~S|<path d="M4 7h16M9.5 7V4.5h5V7M6 7l1 13.5h10L18 7M10 11v5.5M14 11v5.5"/>|,
    "truck" =>
      ~S|<path d="M5 18H3V6a1 1 0 0 1 1-1h10v13M9 18h6M19 18h2v-4l-3-4h-4"/><circle cx="7" cy="18" r="2"/><circle cx="17" cy="18" r="2"/>|,
    "user-circle" =>
      ~S|<circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6.6 18.4a6.5 6.5 0 0 1 10.8 0"/>|,
    "user-minus" =>
      ~S|<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20.5a6.5 6.5 0 0 1 13 0M16 11h6"/>|,
    "user-plus" =>
      ~S|<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20.5a6.5 6.5 0 0 1 13 0M19 8v6M16 11h6"/>|,
    "users" =>
      ~S|<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20.5a6.5 6.5 0 0 1 13 0M15.5 4.8a3.5 3.5 0 0 1 0 6.4M18 14.3a6.5 6.5 0 0 1 3.5 6.2"/>|,
    "user" => ~S|<circle cx="12" cy="8" r="3.5"/><path d="M5.5 20.5a6.5 6.5 0 0 1 13 0"/>|,
    "wrench" =>
      ~S|<path d="M14.6 3.6a5 5 0 0 0-4.8 6.7l-6 6a2 2 0 0 0 2.9 2.9l6-6a5 5 0 0 0 6.7-4.8l-3 3-3-.8-.8-3z"/>|,
    "x-circle" => ~S|<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6"/>|,
    "x-mark" => ~S|<path d="M6 6l12 12M18 6 6 18"/>|
  }

  @names @drawings |> Map.keys() |> Enum.sort()

  @doc "The name of each icon."
  def names, do: @names

  @doc "The inside of the `<svg>` of an icon: its lines, with no colour and no size."
  def drawing(name), do: Map.fetch!(@drawings, name)

  @doc """
  Renders one of our own icons as an inline SVG of 1em.

  An unknown literal `name` gives a compile warning.

  ## Examples

      <.icon name="x-mark" />
      <.icon name="arrow-path" spin />
  """
  attr :name, :string, required: true, values: @names
  attr :spin, :boolean, default: false, doc: "turns the icon, for a pending action"
  attr :rest, :global

  def icon(assigns) do
    assigns = assign(assigns, :drawing, drawing(assigns.name))

    ~H"""
    <svg
      viewBox="0 0 24 24"
      width="1em"
      height="1em"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      focusable="false"
      data-spin={@spin}
      {@rest}
    >
      {Phoenix.HTML.raw(@drawing)}
    </svg>
    """
  end

  @doc """
  The shape of a part of the site: the same in the menu, on the page of the
  organisation, in the parts that need attention and on the heading of its
  page.
  """
  def section(:home), do: "building"
  def section(:tasks), do: "clipboard-check"
  def section(:routines), do: "repeat"
  def section(:calendar), do: "rss"
  def section(:residents), do: "paw"
  def section(:conditions), do: "pulse"
  def section(:groups), do: "paws"
  def section(:housing), do: "kennel"
  def section(:inventory), do: "archive-box"
  def section(:suppliers), do: "truck"
  def section(:expenses), do: "receipt"
  def section(:tools), do: "wrench"
  def section(:dose), do: "calculator"
  def section(:reports), do: "document-chart"
  def section(:lists), do: "list-bullet"
  def section(:members), do: "users"
  def section(:roles), do: "key"
  def section(:transfers), do: "arrows-right-left"
  def section(:partners), do: "link"
  def section(:settings), do: "adjustments"
  def section(:ruby), do: "gem"
  def section(:usage), do: "chart-bar"
  def section(:export), do: "arrow-down-tray"
  def section(:root), do: "shield"
  def section(:notifications), do: "bell"
  def section(:journal), do: "book-open"
  def section(:measurements), do: "chart-line"
  def section(:photos), do: "photo"
  def section(:timeline), do: "timeline"

  @entry_kinds ~w(examination diagnosis measurement procedure vaccination prescription dose
                   placement group behaviour general)a

  @doc """
  The shape of a kind of journal entry (`Rescord.Journal.EntryKind`), or
  `nil`. A kind can be text, as in the copy of a transfer: it then matches
  a known kind or nothing, and makes no atom.
  """
  def entry_kind(kind) when is_binary(kind) do
    Enum.find_value(@entry_kinds, &(Atom.to_string(&1) == kind && entry_kind(&1)))
  end

  def entry_kind(:examination), do: "stethoscope"
  def entry_kind(:diagnosis), do: "pulse"
  def entry_kind(:measurement), do: "scale"
  def entry_kind(:procedure), do: "scissors"
  def entry_kind(:vaccination), do: "syringe"
  def entry_kind(:prescription), do: "pill-bottle"
  def entry_kind(:dose), do: "pill"
  def entry_kind(:placement), do: "kennel"
  def entry_kind(:group), do: "paws"
  def entry_kind(:behaviour), do: "eye"
  def entry_kind(:general), do: "document-text"
  def entry_kind(_kind), do: nil

  @doc "The shape of a kind of stock movement."
  def movement(:received), do: "door-in"
  def movement(:used), do: "minus-circle"
  def movement(:moved), do: "arrow-right"
  def movement(:discarded), do: "trash"
  def movement(:counted), do: "hashtag"
end
