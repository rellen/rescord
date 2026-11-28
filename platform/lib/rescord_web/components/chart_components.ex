defmodule RescordWeb.ChartComponents do
  @moduledoc """
  The charts of Rescord (ADR 0080): a line chart of values over time, and a
  sparkline. Each is SVG that the server writes, with no script and no
  library. `RescordWeb.Chart` holds the geometry.

  ## How a chart is drawn

  The `<svg>` has no `viewBox`, so one unit is one CSS pixel at each width,
  and a place is a percentage: `<circle cx="43%" cy="20%" r="4" />`. A dot
  stays round and a word keeps its size on a phone and on a wide screen.
  Only the line is in a nested `<svg>` that stretches
  (`preserveAspectRatio="none"`), with a stroke that does not stretch.

  The numbers of the value axis and the two dates below the plot are HTML,
  so they take the font of the page. The stylesheet has the look, in the
  section `charts` of `components.css`: the markup has no class, no colour
  and no `style`.

  ## What a person who does not see the chart gets

  The `<svg>` is one image (`role="img"`). Its name is `title`, and its
  description is `summary`, which the page also shows below the chart as
  the caption of the figure. The axes and the layer of the points are
  `aria-hidden`. A page that draws a chart also shows its values as a table.
  A chart never holds a value that the page says nowhere else.

  ## Points that answer

  With `pick`, each point takes a press: the event `pick` gets the `id` of
  the point as `"point"`. The band of the plot nearest to a point takes the
  press, and not the dot alone. A pointer that hovers sees the words of the
  point at once. Give the point that the person chose as `selected`.
  """

  use RescordWeb, :html

  alias RescordWeb.Chart
  alias RescordWeb.JournalWords

  # More points than this, and the chart draws the line with no dot for
  # each point. More than `@answering`, and no point takes a press.
  @dots 40
  @answering 120

  @doc """
  A line chart of one series of values over time.

  Each point is a map with `id`, `at` (a `DateTime`), `value` (a `Decimal`)
  and `label`, the words of the point: `21 November 2026: 1,050 g`.

  ## Examples

      <.line_chart
        id="weight"
        title="Weight of Biscuit"
        summary="12 measurements from 3 October 2026 to 28 November 2026."
        points={@points}
        from="3 October 2026"
        to="28 November 2026"
        pick="pick"
        selected={@selected}
      />
  """
  attr :id, :string, required: true
  attr :title, :string, required: true, doc: "the name of the image"
  attr :summary, :string, required: true, doc: "what the chart shows, in a sentence or two"
  attr :points, :list, required: true
  attr :from, :string, required: true, doc: "the words below the left end of the plot"
  attr :to, :string, required: true, doc: "the words below the right end of the plot"
  attr :scale, Chart.Scale, default: nil, doc: "a scale that several charts share"
  attr :context, :list, default: [], doc: "other series, drawn behind in grey: lists of points"
  attr :tick, :any, default: &JournalWords.number/1, doc: "writes the number of a tick"
  attr :pick, :string, default: nil, doc: "the event of a press on a point"
  attr :selected, :any, default: nil, doc: "the id of the point that the person chose"

  def line_chart(assigns) do
    scale = assigns.scale || Chart.scale(assigns.points)
    marks = Chart.marks(assigns.points, scale)
    count = length(marks)

    assigns =
      assign(assigns,
        scale: scale,
        marks: marks,
        labels: Map.new(assigns.points, &{&1.id, &1.label}),
        newest: List.last(marks),
        line: Chart.path(marks),
        behind: Enum.map(assigns.context, &(&1 |> Chart.marks(scale) |> Chart.path())),
        grid: for(tick <- scale.ticks, do: Chart.y(tick, scale)),
        dots?: count <= @dots,
        answering?: count <= @answering
      )

    ~H"""
    <figure data-chart id={@id}>
      <div data-plot>
        <ol data-ticks aria-hidden="true">
          <li :for={tick <- Enum.reverse(@scale.ticks)}>{@tick.(tick)}</li>
        </ol>
        <svg role="img" aria-label={@title} aria-describedby={"#{@id}-summary"} focusable="false">
          <g data-grid>
            <line :for={y <- @grid} x1="0" x2="100%" y1={"#{y}%"} y2={"#{y}%"} />
          </g>
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" width="100%" height="100%">
            <path :for={path <- @behind} data-context d={path} />
            <path data-line d={@line} />
          </svg>
          <g :if={@dots?} data-dots>
            <circle :for={mark <- @marks} cx={"#{mark.x}%"} cy={"#{mark.y}%"} r="4" />
          </g>
          <circle :if={!@dots?} data-newest cx={"#{@newest.x}%"} cy={"#{@newest.y}%"} r="4" />
          <g :if={@answering?} data-points aria-hidden="true">
            <g
              :for={mark <- @marks}
              data-selected={mark.id == @selected}
              phx-click={@pick}
              phx-value-point={@pick && mark.id}
            >
              <rect x={"#{mark.band_x}%"} y="0" width={"#{mark.band_width}%"} height="100%" />
              <line x1={"#{mark.x}%"} x2={"#{mark.x}%"} y1="0" y2="100%" />
              <circle cx={"#{mark.x}%"} cy={"#{mark.y}%"} r="6" />
              <text x={"#{mark.x}%"} y="-10" text-anchor={mark.anchor}>{@labels[mark.id]}</text>
            </g>
          </g>
        </svg>
        <p data-span aria-hidden="true"><span>{@from}</span><span>{@to}</span></p>
      </div>
      <figcaption id={"#{@id}-summary"}>{@summary}</figcaption>
    </figure>
    """
  end

  @doc """
  A sparkline: the line of a series with no axis and no word, beside a
  value that the page writes. It is decoration, so it is `aria-hidden`:
  the words beside it say the value and its change.

  ## Examples

      <.sparkline points={@points} />
  """
  attr :points, :list, required: true
  attr :scale, Chart.Scale, default: nil, doc: "a scale that several sparklines share"
  attr :context, :list, default: [], doc: "other series, drawn behind in grey"
  attr :rest, :global

  def sparkline(assigns) do
    scale = assigns.scale || Chart.scale(assigns.points)
    marks = if scale, do: Chart.marks(assigns.points, scale), else: []

    assigns =
      assign(assigns,
        newest: List.last(marks),
        line: Chart.path(marks),
        behind:
          if(scale,
            do: Enum.map(assigns.context, &(&1 |> Chart.marks(scale) |> Chart.path())),
            else: []
          )
      )

    ~H"""
    <svg data-spark aria-hidden="true" focusable="false" {@rest}>
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" width="100%" height="100%">
        <path :for={path <- @behind} data-context d={path} />
        <path :if={@line != ""} data-line d={@line} />
      </svg>
      <circle :if={@newest} cx={"#{@newest.x}%"} cy={"#{@newest.y}%"} r="3" />
    </svg>
    """
  end
end
