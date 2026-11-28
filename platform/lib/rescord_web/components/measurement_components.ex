defmodule RescordWeb.MeasurementComponents do
  @moduledoc """
  The parts of the pages that show measurements over time (ADR 0080): the
  choice of a time range, the card of one kind of measurement with its
  chart and its table, the form that records a measurement, and the tiles
  of the members of a group.
  """

  use RescordWeb, :html

  import RescordWeb.ChartComponents

  alias Rescord.Journal.Series
  alias RescordWeb.MeasurementWords

  @ranges [{"all", "All"}, {"365", "1 year"}, {"90", "90 days"}, {"30", "30 days"}]

  @doc "The ranges that a page offers, each as `{key, words}`."
  def ranges, do: @ranges

  @doc """
  The number of days of a range for the text of a parameter, or `nil` for
  each measurement. A text that is no range is each measurement too.
  """
  @spec days(term) :: pos_integer | nil
  def days(key) when key in ["365", "90", "30"], do: String.to_integer(key)
  def days(_key), do: nil

  @doc """
  The choice of the time that the charts of a page show. Each choice is a
  link, so the address of the page holds the choice.
  """
  attr :chosen, :any, required: true, doc: "the number of days, or nil for each measurement"
  attr :path, :any, required: true, doc: "a function from the key of a range to the path"

  def range_choice(assigns) do
    assigns = assign(assigns, ranges: @ranges)

    ~H"""
    <nav aria-label="Time range" data-choice>
      <.link
        :for={{key, words} <- @ranges}
        patch={@path.(key)}
        aria-current={days(key) == @chosen && "true"}
      >
        {words}
      </.link>
    </nav>
    """
  end

  @doc """
  The card of one kind of measurement: the newest value, its change, the
  chart of the time range, and the measurements of that range as a table.

  `series` has each measurement of the kind, and `shown` has those of the
  time range.
  """
  attr :series, Series, required: true
  attr :shown, Series, required: true
  attr :organisation, :any, required: true
  attr :resident, :any, required: true

  attr :selected, :any,
    default: nil,
    doc: "the id of the entry of the point that the person chose"

  def measure(assigns) do
    date = MeasurementWords.date_of(assigns.series, assigns.organisation)
    newest = Series.newest(assigns.series)
    points = assigns.shown.points

    assigns =
      assign(assigns,
        date: date,
        newest: newest,
        points: points,
        chart_points:
          for point <- points do
            %{
              id: point.entry_id,
              at: point.at,
              value: point.value,
              label: "#{date.(point.at)}: #{MeasurementWords.shown(assigns.series, point)}"
            }
          end,
        picked: Enum.find(points, &(&1.entry_id == assigns.selected)),
        rows:
          Enum.sort_by(
            Enum.map(points, &{:point, &1}) ++ Enum.map(assigns.shown.others, &{:other, &1}),
            fn {_kind, point} -> DateTime.to_unix(point.at, :microsecond) end,
            :desc
          )
      )

    ~H"""
    <article data-measure id={"measure-#{@series.kind_id}"}>
      <h2>{@series.label}</h2>
      <p data-figure>
        <strong>{MeasurementWords.shown(@series, @newest)}</strong>
        <span>{@date.(@newest.at)}</span>
      </p>
      <.change series={@series} point={@newest} date={@date} />
      <.line_chart
        :if={length(@points) > 1}
        id={"chart-#{@series.kind_id}"}
        title={"#{@series.label} of #{name(@resident)}#{unit_words(@series)}"}
        summary={MeasurementWords.summary(@shown, @date)}
        points={@chart_points}
        from={@date.(List.first(@points).at)}
        to={@date.(List.last(@points).at)}
        pick="pick"
        selected={@selected}
      />
      <p :if={length(@points) == 1}>
        One measurement in this time. A chart starts with the second one.
      </p>
      <p :if={@points == []}>No measurement in this time.</p>
      <p :if={@picked} role="status" data-picked>
        <strong>{MeasurementWords.shown(@series, @picked)}</strong>
        on {@date.(@picked.at)}.
        <span :if={@picked.change}>
          {MeasurementWords.change_words(@series, @picked, @date)}.
        </span>
        <.link navigate={entry_path(@organisation, @resident, @picked.entry_id)}>
          Open the entry
        </.link>
      </p>
      <p :if={@shown.others != []}>
        <.icon name="information-circle" />
        {others_words(@shown.others, @series)}
      </p>
      <details :if={@rows != []} id={"table-#{@series.kind_id}"}>
        <summary>{count_words(length(@rows))} as a table</summary>
        <table>
          <thead>
            <tr>
              <th scope="col">When</th>
              <th scope="col">Value</th>
              <th scope="col">Change</th>
              <th scope="col">Note</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={{kind, point} <- @rows}
              id={"point-#{point.entry_id}"}
              aria-current={point.entry_id == @selected && "true"}
            >
              <th scope="row">
                <.link navigate={entry_path(@organisation, @resident, point.entry_id)}>
                  {@date.(point.at)}
                </.link>
              </th>
              <td :if={kind == :point} data-label="Value">
                {MeasurementWords.shown(@series, point)}
                <small :if={point.converted?}>
                  recorded as {MeasurementWords.recorded(point)}
                </small>
              </td>
              <td :if={kind == :other} data-label="Value">{MeasurementWords.recorded(point)}</td>
              <%!-- On one line: an empty cell is not on the card of a phone. --%>
              <td :if={kind == :point} data-label="Change" phx-no-format><.change_cell series={@series} point={point} /></td>
              <td :if={kind == :other} data-label="Change">Not in the chart</td>
              <td data-label="Note">{point.note}</td>
            </tr>
          </tbody>
        </table>
      </details>
    </article>
    """
  end

  # The change of the newest value from the one before: a shape and words.
  attr :series, Series, required: true
  attr :point, :any, required: true
  attr :date, :any, required: true

  defp change(assigns) do
    assigns = assign(assigns, change: MeasurementWords.change(assigns.series, assigns.point))

    ~H"""
    <p :if={@change} data-change={elem(@change, 0)}>
      <.icon name={change_icon(elem(@change, 0))} />
      {MeasurementWords.change_words(@series, @point, @date)}
    </p>
    """
  end

  attr :series, Series, required: true
  attr :point, :any, required: true

  defp change_cell(assigns) do
    assigns = assign(assigns, change: MeasurementWords.change(assigns.series, assigns.point))

    ~H"""
    <span :if={@change} data-change={elem(@change, 0)}>
      <.icon name={change_icon(elem(@change, 0))} />
      {short_change(@change)}
    </span>
    """
  end

  defp change_icon(:up), do: "arrow-up"
  defp change_icon(:down), do: "arrow-down"
  defp change_icon(:same), do: "equals"

  defp short_change({:up, amount}), do: "#{amount} more"
  defp short_change({:down, amount}), do: "#{amount} less"
  defp short_change({:same, _amount}), do: "The same"

  defp count_words(1), do: "The measurement"
  defp count_words(count), do: "The #{count} measurements"

  defp unit_words(%Series{unit_label: nil}), do: ""
  defp unit_words(%Series{unit_label: label}), do: ", in #{label}"

  defp others_words([_one], series),
    do:
      "One measurement is not in the chart: it is not in #{unit_name(series)}. The table has it."

  defp others_words(others, series),
    do:
      "#{length(others)} measurements are not in the chart: they are not in #{unit_name(series)}. The table has them."

  defp unit_name(%Series{unit_label: nil}), do: "the unit of the newest one, which has none"
  defp unit_name(%Series{unit_label: label}), do: "#{label}, or in a unit that converts to it"

  defp name(resident), do: resident.name || "a resident with no name"

  defp entry_path(organisation, resident, entry_id),
    do: ~p"/o/#{organisation.short_name}/residents/#{resident.id}/journal?#{[entry: entry_id]}"

  @doc """
  The form that records a measurement, for a person who can write to the
  journal. The page gives the units of the chosen kind.
  """
  attr :form, :any, required: true
  attr :kinds, :list, required: true
  attr :units, :list, required: true

  attr :unit_needed?, :boolean,
    default: false,
    doc: "the chosen kind has a standard unit, so a measurement needs a unit"

  def record_form(assigns) do
    ~H"""
    <details id="record">
      <summary><.icon name="plus" /> Record a measurement</summary>
      <.form for={@form} id="measurement" phx-change="choose" phx-submit="record">
        <.input
          field={@form[:measure_kind_id]}
          type="select"
          label="What was measured"
          prompt="Choose"
          options={@kinds}
          required
        />
        <.input field={@form[:value]} type="decimal" label="Value" required />
        <.input
          field={@form[:unit_id]}
          type="select"
          label="Unit"
          prompt={if @unit_needed?, do: nil, else: "No unit"}
          options={@units}
          required={@unit_needed?}
        />
        <.input field={@form[:at]} type="datetime-local" label="When it was measured, if not now" />
        <.input field={@form[:note]} type="textarea" label="Note" maxlength="2000" />
        <footer><.button type="submit">Record the measurement</.button></footer>
      </.form>
    </details>
    """
  end

  @doc """
  The newest measurement of each kind for the page of a resident: the
  value, its date, and a sparkline of the kind.
  """
  attr :series, :list, required: true
  attr :organisation, :any, required: true

  def newest_values(assigns) do
    ~H"""
    <dl data-measures>
      <div :for={series <- @series}>
        <dt>{series.label}</dt>
        <dd>
          <.newest_value series={series} organisation={@organisation} />
        </dd>
      </div>
    </dl>
    """
  end

  attr :series, Series, required: true
  attr :organisation, :any, required: true

  defp newest_value(assigns) do
    date = MeasurementWords.date_of(assigns.series, assigns.organisation)
    newest = Series.newest(assigns.series)

    assigns =
      assign(assigns,
        date: date,
        newest: newest,
        change: MeasurementWords.change(assigns.series, newest)
      )

    ~H"""
    <span>{MeasurementWords.shown(@series, @newest)}, {@date.(@newest.at)}</span>
    <.sparkline :if={length(@series.points) > 1} points={@series.points} />
    <small :if={@change} data-change={elem(@change, 0)}>
      <.icon name={change_icon(elem(@change, 0))} />
      {short_change(@change)}
    </small>
    """
  end

  @doc """
  The members of a group with one kind of measurement: a tile for each
  member, with its newest value, its change, and its line in front of the
  lines of the other members. Each tile has the same scale.

  A member is a map with `resident`, `series` (its series of the kind, or
  `nil`), `shown` (the points of the time range) and `charted?`: whether
  its series is in the unit of the others. A member in another unit has
  its value and no chart.
  """
  attr :members, :list, required: true
  attr :scale, :any, required: true
  attr :organisation, :any, required: true
  attr :range, :string, required: true

  def member_tiles(assigns) do
    ~H"""
    <ul data-multiples>
      <li :for={member <- @members}>
        <.link navigate={
          ~p"/o/#{@organisation.short_name}/residents/#{member.resident.id}/measurements?#{[range: @range]}"
        }>
          {member.resident.name || "A resident with no name"}
        </.link>
        <.member_tile
          :if={member.series}
          member={member}
          others={for other <- @members, other != member, other.charted?, do: other.shown.points}
          scale={@scale}
          organisation={@organisation}
        />
        <small :if={is_nil(member.series)}>No measurement</small>
      </li>
    </ul>
    """
  end

  attr :member, :any, required: true
  attr :others, :list, required: true
  attr :scale, :any, required: true
  attr :organisation, :any, required: true

  defp member_tile(assigns) do
    series = assigns.member.series
    newest = Series.newest(series)

    assigns =
      assign(assigns,
        series: series,
        newest: newest,
        date: MeasurementWords.date_of(series, assigns.organisation),
        change: MeasurementWords.change(series, newest)
      )

    ~H"""
    <strong>{MeasurementWords.shown(@series, @newest)}</strong>
    <small>{@date.(@newest.at)}</small>
    <small :if={@change} data-change={elem(@change, 0)}>
      <.icon name={change_icon(elem(@change, 0))} />
      {short_change(@change)}
    </small>
    <.sparkline
      :if={@member.charted? and @scale != nil and @member.shown.points != []}
      points={@member.shown.points}
      context={@others}
      scale={@scale}
    />
    <small :if={!@member.charted?}>In another unit, so not in a chart</small>
    """
  end
end
