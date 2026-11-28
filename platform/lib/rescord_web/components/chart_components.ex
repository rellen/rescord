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
  attr :step, :boolean, default: false, doc: "a count that holds until the next point (ADR 0118)"

  attr :rules, :list,
    default: [],
    doc:
      "values drawn as a dashed rule across the plot, such as a capacity; give a scale that holds them"

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
        line: if(assigns.step, do: Chart.step_path(marks), else: Chart.path(marks)),
        rule_places: for(value <- assigns.rules, do: Chart.y(value, scale)),
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
          <line
            :for={y <- @rule_places}
            data-rule
            x1="0"
            x2="100%"
            y1={"#{y}%"}
            y2={"#{y}%"}
          />
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

  @doc """
  Bars above and below a line (ADR 0118): for each period, a bar up for one
  count and a bar down for another, such as the arrivals and the
  departures of each week. It is one image with a name and a description,
  and the page gives its values as a table too.

  ## Examples

      <.updown_bars
        id="moves"
        title="Arrivals and departures of each week"
        summary="31 arrivals and 27 departures in 52 weeks."
        pairs={[{2, 0}, {1, 3}]}
        from="1 December 2025"
        to="23 November 2026"
      />
  """
  attr :id, :string, required: true
  attr :title, :string, required: true, doc: "the name of the image"
  attr :summary, :string, required: true, doc: "what the bars show, in a sentence or two"

  attr :pairs, :list,
    required: true,
    doc: "a `{up, down}` count for each period, the oldest first"

  attr :from, :string, required: true, doc: "the words below the left end"
  attr :to, :string, required: true, doc: "the words below the right end"

  def updown_bars(assigns) do
    assigns = assign(assigns, :bars, Chart.bars(assigns.pairs))

    ~H"""
    <figure data-chart id={@id}>
      <svg
        data-bars
        role="img"
        aria-label={@title}
        aria-describedby={"#{@id}-summary"}
        focusable="false"
      >
        <g :for={bar <- @bars}>
          <rect
            :if={bar.up > 0}
            data-up
            x={"#{bar.x}%"}
            y={"#{50 - bar.up}%"}
            width={"#{bar.width}%"}
            height={"#{bar.up}%"}
          />
          <rect
            :if={bar.down > 0}
            data-down
            x={"#{bar.x}%"}
            y="50%"
            width={"#{bar.width}%"}
            height={"#{bar.down}%"}
          />
        </g>
        <line x1="0" x2="100%" y1="50%" y2="50%" />
      </svg>
      <p data-span aria-hidden="true"><span>{@from}</span><span>{@to}</span></p>
      <figcaption id={"#{@id}-summary"}>{@summary}</figcaption>
    </figure>
    """
  end

  @doc """
  A heat map (ADR 0116): a table whose cells are values, each on a step of
  one ramp. It is its own text alternative: a screen reader reads a cell
  with the header of its row and of its column, "Tuesday, week of 6 July
  2026, 7 of 8 on time". It stays a grid on a phone.

  A column and a row each have `label`, the short words that show, and
  `words`, the whole words for a screen reader, or `nil` when the label
  says it all. A row has `cells`, one for each column, each a map with:

    * `level`: `0` for nothing to count, `1` to `4` for the steps of the
      ramp, `:total` for a count that is no step, such as a total
      (ADR 0119), or `:none` for a cell with no value, such as a day to
      come
    * `words`: the value in words
    * `mark`: a dot, for a cell that needs a look (optional)
    * `today`: an outline, for the cell of today (optional)
    * `day`: the day of the month, which a table of counts shows small in
      the corner of the cell, and not to a screen reader (optional)
    * `id`: what a press on the cell gives the event `pick` as `"cell"`
      (optional)

  The variant `"numbers"` shows the words of each cell, for a table of
  counts. With no variant, the cells are squares and their words are for a
  screen reader. Like a point of a line chart, a cell takes a press and no
  keyboard focus: the table itself holds each value.

  ## Examples

      <.heat_table
        id="calendar"
        summary="91% of 2,410 tasks were done on time."
        columns={[%{label: "Jun", words: "Week of 1 June 2026"}]}
        rows={[%{label: "Mon", words: "Monday", cells: [%{level: 3, words: "7 of 8 on time"}]}]}
        pick="pick"
      />
  """
  attr :id, :string, required: true
  attr :summary, :string, required: true, doc: "what the table shows, in a sentence or two"
  attr :columns, :list, required: true
  attr :rows, :list, required: true
  attr :corner, :string, default: nil, doc: "the header of the column of the names of the rows"
  attr :variant, :string, default: nil, values: [nil, "numbers"]
  attr :pick, :string, default: nil, doc: "the event of a press on a cell"
  attr :selected, :any, default: nil, doc: "the id of the cell that the person chose"

  def heat_table(assigns) do
    ~H"""
    <table data-heat={@variant || true} id={@id}>
      <caption id={"#{@id}-summary"}>{@summary}</caption>
      <thead>
        <tr>
          <td :if={is_nil(@corner)}></td>
          <th :if={@corner} scope="col"><span data-words>{@corner}</span></th>
          <th :for={column <- @columns} scope="col"><.heat_words of={column} /></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @rows}>
          <th scope="row"><.heat_words of={row} /></th>
          <td
            :for={cell <- row.cells}
            data-level={cell.level}
            data-mark={cell[:mark]}
            data-today={cell[:today]}
            data-day={cell[:day]}
            data-selected={@selected != nil and cell[:id] == @selected}
            phx-click={@pick && cell[:id] && @pick}
            phx-value-cell={@pick && cell[:id]}
          >
            <span :if={cell.level != :none}>{cell.words}</span>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :of, :map, required: true

  defp heat_words(%{of: %{words: words}} = assigns) when is_binary(words) do
    ~H"""
    <span aria-hidden="true">{@of.label}</span><span data-words>{@of.words}</span>
    """
  end

  defp heat_words(assigns), do: ~H"{@of.label}"
end
