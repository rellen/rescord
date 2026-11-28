defmodule RescordWeb.HoursInsightsLive do
  @moduledoc """
  When the care of an organisation is done, at
  `/o/<short name>/insights/hours` (ADR 0120): which hours are busy, and
  which hours slip?

  A punch card has a row for each day of the week and a column for each
  hour, with a dot as large as the tasks done in that hour over the last
  12 weeks. A row below has, for each hour, the share of the tasks due in
  it that were done more than an hour late.

  Each member can open the page: it reads the tasks as that member. It
  counts the tasks of the refuge, and never the work of a person.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents
  import RescordWeb.InsightComponents

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.{Chart, InsightWords, JournalWords, Locale}

  @weeks 12

  # The bounds of the steps of the row of the hours: the percent of the
  # tasks due in an hour that were done late.
  @bounds [5, 15, 30]

  # A Monday, for the names of the days of the week.
  @monday ~D[2026-11-23]

  @impl true
  def mount(_params, _session, socket) do
    today = Accounts.today(socket.assigns.organisation)
    first = hd(Chart.weeks(today, @weeks))

    {:ok, hours} =
      Tasks.hours(first, today,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.organisation
      )

    {:ok,
     assign(socket,
       page_title: "When the care is done",
       weeks: @weeks,
       first: first,
       hours: hours
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # An hour shows its time each six hours, and its words run on over the
  # next hours.
  defp columns do
    for hour <- 0..23 do
      %{
        label: if(rem(hour, 6) == 0, do: Locale.time(Time.new!(hour, 0, 0)), else: ""),
        words: "The hour from #{Locale.time(Time.new!(hour, 0, 0))}"
      }
    end
  end

  defp weekday(day), do: Date.add(@monday, day - 1)

  defp done_rows(done) do
    greatest = done |> Map.values() |> Enum.max()

    for day <- 1..7 do
      %{
        label: Locale.weekday(weekday(day), :short),
        words: Locale.weekday(weekday(day)),
        cells:
          for hour <- 0..23, count = Map.fetch!(done, {day, hour}) do
            %{
              level: Chart.level(count, greatest),
              words: Locale.count(count, "task done", "tasks done")
            }
          end
      }
    end
  end

  defp late_rows(due) do
    [
      %{
        label: "Late",
        words: "Done late",
        cells:
          for hour <- 0..23, %{done: done, late: late} = Map.fetch!(due, hour) do
            %{level: Chart.share_level(late, done, @bounds), words: late_words(late, done)}
          end
      }
    ]
  end

  defp late_words(_late, 0), do: "No task done"

  defp late_words(late, done),
    do: "#{JournalWords.number(late)} of #{InsightWords.tasks(done)} late"

  defp done_summary(done, weeks) do
    total = done |> Map.values() |> Enum.sum()

    if total == 0 do
      "No task was done in the last #{weeks} weeks."
    else
      {{day, hour}, most} = Enum.max_by(done, fn {key, count} -> {count, key} end)

      "#{Locale.count(total, "task was done", "tasks were done")} in the last #{weeks} weeks. " <>
        "The busiest hour was " <>
        "#{Locale.weekday(weekday(day))} from #{Locale.time(Time.new!(hour, 0, 0))}, " <>
        "with #{Locale.count(most, "task done", "tasks done")}."
    end
  end

  defp late_summary(due) do
    done = due |> Map.values() |> Enum.map(& &1.done) |> Enum.sum()
    late = due |> Map.values() |> Enum.map(& &1.late) |> Enum.sum()

    cond do
      done == 0 ->
        "No task was done, so no hour slipped."

      late == 0 ->
        "Each task was done within an hour after its time."

      true ->
        {hour, worst} =
          due
          |> Enum.filter(fn {_hour, counts} -> counts.late > 0 end)
          |> Enum.max_by(fn {hour, counts} -> {counts.late / counts.done, -hour} end)

        "#{InsightWords.percent(late, done)} of the tasks done were done more than an hour after " <>
          "their time. The hour from #{Locale.time(Time.new!(hour, 0, 0))} slipped the most: " <>
          "#{late_words(worst.late, worst.done)}."
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
        When the care is done
        <:subtitle>Which hours are busy at {@organisation.name}, and which hours slip?</:subtitle>
      </.header>

      <section aria-labelledby="done-heading">
        <h2 id="done-heading">Tasks done in each hour</h2>
        <p>
          The tasks of the last {@weeks} weeks, from {Locale.date(@first)}, by the day and the hour
          in which they were done. The more tasks, the larger the dot.
        </p>
        <figure data-chart>
          <.heat_table
            id="done"
            variant="dots"
            summary={done_summary(@hours.done, @weeks)}
            columns={columns()}
            rows={done_rows(@hours.done)}
            corner="Day of the week"
          />
        </figure>
      </section>

      <section aria-labelledby="late-heading">
        <h2 id="late-heading">Hours that slip</h2>
        <p>
          For each hour, the tasks due in it and done, and how many of them were done more than an
          hour after their time. The larger the share, the stronger the colour.
        </p>
        <figure data-chart>
          <.heat_table
            id="late"
            summary={late_summary(@hours.due)}
            columns={columns()}
            rows={late_rows(@hours.due)}
          />
        </figure>
        <.heat_key steps={["Under 5%", "5%", "15%", "30% or more"]} />
      </section>
    </Layouts.app>
    """
  end
end
