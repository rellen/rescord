defmodule RescordWeb.ResidentsInsightsLive do
  @moduledoc """
  The residents in care over a year, at
  `/o/<short name>/insights/residents` (ADR 0118).

  Four figures: the residents in care today, the arrivals and the
  departures of the last 12 months, and the days on which the refuge had
  more residents than room. A step line of the residents in care at the end
  of each day, with a dashed rule at the room of the housing. Bars of the
  arrivals (up) and departures (down) of each week. The counts of each
  week as a table. A species narrows each of them, but the room, which is
  the room of the whole housing.

  Each member can open the page: it reads the residents and the housing
  as that member. It reads only the values that it knows from what the
  browser sends, and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents
  import RescordWeb.InsightComponents

  alias Rescord.{Accounts, Lists, Locations, Residents}
  alias RescordWeb.{Chart, InsightWords, JournalWords, Locale}

  @days 365
  @weeks 52

  @impl true
  def mount(_params, _session, socket) do
    species =
      case Lists.values(:species, options(socket)) do
        {:ok, values} -> Enum.map(values, &{to_string(&1.label), &1.id})
        {:error, _error} -> []
      end

    {:ok, room} = Locations.room(options(socket))

    {:ok,
     socket
     |> assign(page_title: "Residents in care", species: species, room: room)
     |> assign_counts(nil)}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_counts(socket, species_id) do
    today = Accounts.today(socket.assigns.organisation)
    first = Date.add(today, -(@days - 1))
    {:ok, stays} = Residents.stays([species: species_id] ++ options(socket))

    census = Residents.in_care_by_day(stays, first, today)
    by_day = Map.new(census)
    weeks = Residents.moves_by_week(stays, Chart.weeks(today, @weeks))
    room = socket.assigns.room

    assign(socket,
      today: today,
      first: first,
      census: census,
      weeks:
        for {monday, arrivals, departures} <- weeks do
          last = Enum.min([Date.add(monday, 6), today], Date)

          %{
            monday: monday,
            in_care: Map.get(by_day, last),
            arrivals: arrivals,
            departures: departures
          }
        end,
      arrivals: Enum.count(stays, &in_window?(&1.arrived_on, first, today)),
      departures:
        Enum.count(stays, &(&1.departed_on && in_window?(&1.departed_on, first, today))),
      over: if(room, do: Enum.filter(census, fn {_, count} -> count > room end), else: []),
      form: to_form(%{"species_id" => species_id || ""}, as: :residents)
    )
  end

  defp in_window?(date, first, last),
    do: Date.compare(date, first) != :lt and Date.compare(date, last) != :gt

  @impl true
  def handle_event("species", %{"residents" => fields}, socket) when is_map(fields) do
    # Only a species of the list of this organisation.
    species_id =
      Enum.find_value(socket.assigns.species, fn {_label, id} ->
        if id == fields["species_id"], do: id
      end)

    {:noreply, assign_counts(socket, species_id)}
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # A point of the line for each day, at its middle.
  defp points(census) do
    for {date, count} <- census do
      %{
        id: Date.to_iso8601(date),
        at: DateTime.new!(date, ~T[12:00:00]),
        value: Decimal.new(count),
        label: "#{Locale.date(date)}: #{InsightWords.residents(count)}"
      }
    end
  end

  # The scale holds the room too, so its rule is on the plot.
  defp scale(points, nil), do: Chart.scale(points)
  defp scale(points, room), do: Chart.scale([%{hd(points) | value: Decimal.new(room)} | points])

  defp rules(nil), do: []
  defp rules(room), do: [Decimal.new(room)]

  defp census_summary(census, room, over) do
    {_today, now} = List.last(census)
    {most_on, most} = Enum.max_by(census, fn {_, count} -> count end, fn -> {nil, 0} end)

    now_words =
      case room do
        nil ->
          "#{InsightWords.in_care(now)} today."

        room ->
          "#{InsightWords.in_care(now)} today, and the housing has room for #{JournalWords.number(room)}."
      end

    rest =
      case {room, over} do
        {nil, _} ->
          " The most in the last 12 months was #{JournalWords.number(most)}, on #{Locale.date(most_on)}."

        {_room, []} ->
          " The refuge had no more residents than room on any day of the last 12 months."

        {room, [{first_over, _} | _]} ->
          " It had more than #{JournalWords.number(room)} on #{InsightWords.days(length(over))} of the last 12 months, the first on #{Locale.date(first_over)}."
      end

    now_words <> rest
  end

  defp moves_summary(weeks, arrivals, departures) do
    {busiest, _, _} =
      weeks
      |> Enum.map(&{&1.monday, &1.arrivals, &1.departures})
      |> Enum.max_by(fn {_, arrivals, _} -> arrivals end, fn -> {nil, 0, 0} end)

    most = Enum.max(Enum.map(weeks, & &1.arrivals), fn -> 0 end)

    base =
      "#{JournalWords.count(arrivals, "arrival")} and #{JournalWords.count(departures, "departure")} in the last 12 months."

    if most > 0,
      do:
        base <>
          " The week of #{Locale.date(busiest)} had the most arrivals, #{JournalWords.number(most)}.",
      else: base
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        points: points(assigns.census),
        days_over: length(assigns.over)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:reports}
    >
      <.header icon={Icons.section(:insights)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/reports"}>Reports</:crumb>
        Residents in care
        <:subtitle>How full {@organisation.name} is, against its room, over 12 months</:subtitle>
      </.header>

      <.form
        :if={@species != []}
        for={@form}
        id="residents-species"
        phx-change="species"
        phx-submit="species"
      >
        <.input
          field={@form[:species_id]}
          type="select"
          label="Species"
          prompt="Each species"
          options={@species}
        />
      </.form>

      <dl data-figures aria-label="Figures">
        <div>
          <dt>In care today</dt>
          <dd data-value>{JournalWords.number(elem(List.last(@census), 1))}</dd>
          <dd :if={@room}>room for {JournalWords.number(@room)}</dd>
        </div>
        <div>
          <dt>Arrivals</dt>
          <dd data-value>{JournalWords.number(@arrivals)}</dd>
          <dd>in 12 months</dd>
        </div>
        <div>
          <dt>Departures</dt>
          <dd data-value>{JournalWords.number(@departures)}</dd>
          <dd>in 12 months</dd>
        </div>
        <div :if={@room}>
          <dt>Days over room</dt>
          <dd data-value>{JournalWords.number(@days_over)}</dd>
          <dd>in 12 months</dd>
        </div>
      </dl>

      <section aria-labelledby="census-heading">
        <h2 id="census-heading">Residents in care each day</h2>
        <.line_chart
          id="census"
          title="Residents in care at the end of each day"
          summary={census_summary(@census, @room, @over)}
          points={@points}
          scale={scale(@points, @room)}
          rules={rules(@room)}
          step
          from={Locale.date(@first)}
          to={Locale.date(@today)}
        />
        <.key items={
          [{"line", "In care"}] ++ if(@room, do: [{"rule", "Room of the housing"}], else: [])
        } />
      </section>

      <section aria-labelledby="moves-heading">
        <h2 id="moves-heading">Arrivals and departures</h2>
        <.updown_bars
          id="moves"
          title="Arrivals and departures of each week"
          summary={moves_summary(@weeks, @arrivals, @departures)}
          pairs={Enum.map(@weeks, &{&1.arrivals, &1.departures})}
          from={"Week of #{Locale.date(hd(@weeks).monday)}"}
          to={"Week of #{Locale.date(List.last(@weeks).monday)}"}
        />
        <.key items={[{"up", "Arrivals, above the line"}, {"down", "Departures, below it"}]} />

        <details id="weeks-table">
          <summary>The counts of each week as a table</summary>
          <table>
            <caption>
              The residents in care at the end of each week, and its arrivals and departures
            </caption>
            <thead>
              <tr>
                <th scope="col">Week of</th>
                <th scope="col">In care at the end</th>
                <th scope="col">Arrivals</th>
                <th scope="col">Departures</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={week <- Enum.reverse(@weeks)}>
                <th scope="row">{Locale.date(week.monday)}</th>
                <td data-label="In care at the end">
                  {week.in_care && JournalWords.number(week.in_care)}
                </td>
                <td data-label="Arrivals">{JournalWords.number(week.arrivals)}</td>
                <td data-label="Departures">{JournalWords.number(week.departures)}</td>
              </tr>
            </tbody>
          </table>
        </details>
      </section>
    </Layouts.app>
    """
  end
end
