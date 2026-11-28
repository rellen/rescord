defmodule RescordWeb.CareInsightsLive do
  @moduledoc """
  The care of an organisation, day by day, at
  `/o/<short name>/insights/care` (ADR 0116).

  A calendar of the last 26 weeks has a square for each day, darker for a
  larger share of its tasks done on time, with a dot on a day that has a
  task skipped or overdue. A table of counts has the tasks of each of the
  next 14 days, darker for more. A kind of task narrows both, and a press
  on a day of the calendar says its counts, with a link to its tasks.

  Each member can open the page: it reads the tasks as that member. It
  counts the tasks of the refuge, and never the work of a person. It reads
  only the values that it knows from what the browser sends, and makes no
  atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents
  import RescordWeb.InsightComponents

  alias Rescord.{Accounts, Lists, Tasks}
  alias RescordWeb.{Chart, InsightWords, Locale}

  @weeks 26
  @ahead 14

  # The bounds of the steps of the calendar: the percent of the tasks of a
  # day, whose time has come, that were done on time.
  @bounds [80, 90, 97]

  @impl true
  def mount(_params, _session, socket) do
    kinds =
      case Lists.values(:task_kind, options(socket)) do
        {:ok, values} -> Enum.map(values, &{to_string(&1.label), &1.id})
        {:error, _error} -> []
      end

    {:ok,
     socket
     |> assign(page_title: "Care, day by day", kinds: kinds)
     |> assign_days(nil)}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_days(socket, kind_id) do
    organisation = socket.assigns.organisation
    today = Accounts.today(organisation)
    weeks = Chart.weeks(today, @weeks)

    # The routines make the tasks only so many days ahead: a day after that
    # has no task yet, and is not shown as a day with none.
    ahead = min(@ahead, organisation.task_days_ahead)

    {:ok, days} =
      Tasks.days(hd(weeks), Date.add(today, ahead), [kind: kind_id] ++ options(socket))

    coming = coming(days, today, ahead)
    {columns, rows} = coming_table(coming)

    assign(socket,
      weeks: length(weeks),
      today: today,
      days: days,
      calendar: %{
        columns: week_columns(weeks),
        rows: calendar_rows(weeks, days, today),
        summary: calendar_summary(weeks, days, today)
      },
      coming: %{columns: columns, rows: rows, summary: coming_summary(coming)},
      picked: nil,
      form: to_form(%{"kind_id" => kind_id || ""}, as: :care)
    )
  end

  @impl true
  def handle_event("kind", %{"care" => fields}, socket) when is_map(fields) do
    # Only a kind of the list of this organisation.
    kind_id =
      Enum.find_value(socket.assigns.kinds, fn {_label, id} ->
        if id == fields["kind_id"], do: id
      end)

    {:noreply, assign_days(socket, kind_id)}
  end

  # A day of the calendar, and not one to come.
  def handle_event("pick", %{"cell" => value}, socket) when is_binary(value) do
    picked =
      with {:ok, date} <- Date.from_iso8601(value),
           true <- Map.has_key?(socket.assigns.days, date),
           true <- Date.compare(date, socket.assigns.today) != :gt do
        date
      else
        _other -> socket.assigns.picked
      end

    {:noreply, assign(socket, picked: picked)}
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The head of each week: its month where a month starts.
  defp week_columns(weeks) do
    weeks
    |> Enum.with_index()
    |> Enum.map(fn {monday, index} ->
      before = if index > 0, do: Enum.at(weeks, index - 1)
      starts? = is_nil(before) or before.month != monday.month

      %{
        label: if(starts?, do: Locale.short_month(monday), else: ""),
        words: "Week of #{Locale.date(monday)}"
      }
    end)
  end

  # A row for each day of the week, a cell for each week.
  defp calendar_rows(weeks, days, today) do
    for offset <- 0..6 do
      first = Date.add(hd(weeks), offset)

      %{
        label: Locale.weekday(first, :short),
        words: Locale.weekday(first),
        cells: for(monday <- weeks, do: calendar_cell(Date.add(monday, offset), days, today))
      }
    end
  end

  defp calendar_cell(date, days, today) do
    if Date.compare(date, today) == :gt do
      %{level: :none, words: ""}
    else
      counts = Map.fetch!(days, date)

      %{
        id: Date.to_iso8601(date),
        level: Chart.share_level(counts.on_time, counts.total - counts.upcoming, @bounds),
        words: InsightWords.day(counts),
        mark: counts.skipped + counts.overdue > 0,
        today: date == today
      }
    end
  end

  # The counts of the days from the first of the calendar to today.
  defp past(days, today),
    do: Enum.filter(days, fn {date, _} -> Date.compare(date, today) != :gt end)

  defp calendar_summary(weeks, days, today) do
    past = past(days, today)
    due = Enum.sum_by(past, fn {_, counts} -> counts.total - counts.upcoming end)
    on_time = Enum.sum_by(past, fn {_, counts} -> counts.on_time end)
    span = "from #{Locale.date(hd(weeks))} to #{Locale.date(today)}"

    if due == 0 do
      "No task was due #{span}."
    else
      "#{InsightWords.percent(on_time, due)} of #{InsightWords.tasks(due)} were done on time #{span}." <>
        lowest_week(weeks, past) <> " A press on a day says its counts."
    end
  end

  # The week with the least share done on time, of the weeks with a task.
  defp lowest_week(weeks, past) do
    shares =
      for monday <- weeks,
          sunday = Date.add(monday, 6),
          week =
            Enum.filter(past, fn {date, _} ->
              Date.compare(date, monday) != :lt and Date.compare(date, sunday) != :gt
            end),
          due = Enum.sum_by(week, fn {_, counts} -> counts.total - counts.upcoming end),
          due > 0,
          do: {monday, Enum.sum_by(week, fn {_, counts} -> counts.on_time end), due}

    case shares do
      [_, _ | _] ->
        {monday, on_time, due} = Enum.min_by(shares, fn {_, on_time, due} -> on_time / due end)

        " The week of #{Locale.date(monday)} was the lowest, at #{InsightWords.percent(on_time, due)}."

      _one_or_none ->
        ""
    end
  end

  defp coming(days, today, ahead) do
    for offset <- 1..ahead//1, date = Date.add(today, offset), do: {date, Map.fetch!(days, date)}
  end

  # The days to come as a calendar: a row for each week, a column for each
  # day of the week, and no value in a cell before tomorrow or after the
  # last day.
  defp coming_table([]), do: {[], []}

  defp coming_table(coming) do
    counts = Map.new(coming)
    greatest = coming |> Enum.map(fn {_, counts} -> counts.total end) |> Enum.max()
    {first, _} = hd(coming)
    {last, _} = List.last(coming)
    mondays = Date.range(Date.beginning_of_week(first), Date.beginning_of_week(last), 7)

    columns =
      for offset <- 0..6, date = Date.add(Date.beginning_of_week(first), offset) do
        %{label: Locale.weekday(date, :short), words: Locale.weekday(date)}
      end

    rows =
      for monday <- mondays do
        %{
          label: Locale.short_date(monday),
          words: "Week of #{Locale.date(monday)}",
          cells: for(offset <- 0..6, do: coming_cell(Date.add(monday, offset), counts, greatest))
        }
      end

    {columns, rows}
  end

  defp coming_cell(date, counts, greatest) do
    case Map.fetch(counts, date) do
      {:ok, count} ->
        %{
          level: Chart.level(count.total, greatest),
          words: RescordWeb.JournalWords.number(count.total),
          day: date.day
        }

      :error ->
        %{level: :none, words: ""}
    end
  end

  defp coming_summary([]), do: "The routines make no task for the days after today."

  defp coming_summary(coming) do
    total = Enum.sum_by(coming, fn {_, counts} -> counts.total end)

    if total == 0 do
      "No task is due in the next #{length(coming)} days."
    else
      {busiest, counts} = Enum.max_by(coming, fn {_, counts} -> counts.total end)

      "#{InsightWords.tasks(total)} are due in the next #{length(coming)} days. " <>
        "#{Locale.day(busiest)} has the most, #{InsightWords.tasks(counts.total)}."
    end
  end

  @impl true
  def render(assigns) do
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
        Care, day by day
        <:subtitle>Are the routines of {@organisation.name} kept?</:subtitle>
      </.header>

      <.form :if={@kinds != []} for={@form} id="care-kind" phx-change="kind" phx-submit="kind">
        <.input
          field={@form[:kind_id]}
          type="select"
          label="Kind of task"
          prompt="Each kind"
          options={@kinds}
        />
      </.form>

      <section aria-labelledby="calendar-heading">
        <h2 id="calendar-heading">Tasks done on time</h2>
        <p>
          The last {@weeks} weeks. The more of its tasks a day had done by their time, or within
          an hour after it, the stronger the colour of its square. A dot is a day with a task
          skipped or overdue.
        </p>
        <figure data-chart>
          <.heat_table
            id="calendar"
            summary={@calendar.summary}
            columns={@calendar.columns}
            rows={@calendar.rows}
            corner="Day of the week"
            pick="pick"
            selected={@picked && Date.to_iso8601(@picked)}
          />
        </figure>
        <.heat_key steps={["Under 80%", "80%", "90%", "97% or more"]} mark="Skipped or overdue" />
        <p :if={@picked} role="status" data-picked>
          <strong>{Locale.day(@picked)}</strong>: {InsightWords.day(Map.fetch!(@days, @picked))}.
          <.link navigate={~p"/o/#{@organisation.short_name}/tasks?day=#{Date.to_iso8601(@picked)}"}>
            Open the tasks of this day
          </.link>
        </p>
      </section>

      <section aria-labelledby="coming-heading">
        <h2 id="coming-heading">The next two weeks</h2>
        <p>
          The tasks that the routines and the members have planned for each day after today. The
          small number is the day of the month.
        </p>
        <figure data-chart>
          <.heat_table
            id="coming"
            variant="numbers"
            summary={@coming.summary}
            columns={@coming.columns}
            rows={@coming.rows}
          />
        </figure>
      </section>
    </Layouts.app>
    """
  end
end
