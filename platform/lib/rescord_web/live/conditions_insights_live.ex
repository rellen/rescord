defmodule RescordWeb.ConditionsInsightsLive do
  @moduledoc """
  The conditions of the residents by week, at
  `/o/<short name>/insights/conditions` (ADR 0119): is something spreading?

  A table of counts has a row for each condition, a column for each of the
  last 12 weeks with the new cases of that week, stronger in colour for
  more, and a column of the cases that go on now. A last row holds the
  totals. A case is an episode of a resident (ADR 0083).

  Each member can open the page: it reads the conditions as that member.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents

  alias Rescord.{Accounts, Journal}
  alias RescordWeb.{Chart, JournalWords, Locale}

  @weeks 12

  @impl true
  def mount(_params, _session, socket) do
    today = Accounts.today(socket.assigns.organisation)
    mondays = Chart.weeks(today, @weeks)

    {:ok, counts} =
      Journal.conditions_by_week(mondays,
        actor: socket.assigns.current_user,
        tenant: socket.assigns.organisation
      )

    {:ok,
     assign(socket,
       page_title: "Conditions by week",
       weeks: @weeks,
       mondays: mondays,
       counts: counts
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # A week shows the day of its Monday, and its month above it where a
  # month starts, so that the heads fit the width of a phone.
  defp columns(mondays) do
    mondays
    |> Enum.with_index()
    |> Enum.map(fn {monday, index} ->
      label =
        if index == 0 or monday.day <= 7,
          do: "#{Locale.short_month(monday)} #{JournalWords.number(monday.day)}",
          else: JournalWords.number(monday.day)

      %{label: label, words: "Week of #{Locale.date(monday)}"}
    end)
    |> Enum.concat([%{label: "Now", words: "Going on now"}])
  end

  # Each count is shaded against the most new cases of one condition in one
  # week. The cases that go on, and the totals, are no step of the ramp.
  defp rows(counts) do
    greatest = counts.conditions |> Enum.flat_map(& &1.weeks) |> Enum.max(fn -> 0 end)

    for row <- counts.conditions do
      %{
        label: to_string(row.condition.label),
        words: nil,
        cells:
          Enum.map(
            row.weeks,
            &%{level: Chart.level(&1, greatest), words: JournalWords.number(&1)}
          ) ++
            [total(row.ongoing)]
      }
    end ++
      [
        %{
          label: "All",
          words: "All conditions",
          cells: Enum.map(counts.weeks, &total/1) ++ [total(counts.ongoing)]
        }
      ]
  end

  defp total(count), do: %{level: :total, words: JournalWords.number(count)}

  defp summary(%{new: 0, ongoing: 0}, mondays),
    do: "No condition started in the last #{length(mondays)} weeks, and none goes on now."

  defp summary(%{new: 0} = counts, mondays),
    do:
      "No condition started in the last #{length(mondays)} weeks. " <>
        "#{Locale.count(counts.ongoing, "case goes", "cases go")} on now."

  defp summary(counts, mondays) do
    {condition, count, monday} =
      for row <- counts.conditions,
          {count, monday} <- Enum.zip(row.weeks, mondays),
          reduce: {nil, 0, nil} do
        {_, most, _} = best when count <= most -> best
        _best -> {to_string(row.condition.label), count, monday}
      end

    "#{Locale.count(counts.new, "new case", "new cases")} in the last #{length(mondays)} weeks, " <>
      "and #{Locale.count(counts.ongoing, "case goes", "cases go")} on now. " <>
      "The most in one week was #{Locale.count(count, "new case", "new cases")} of #{condition}, " <>
      "in the week of #{Locale.date(monday)}."
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
        Conditions by week
        <:subtitle>Is something spreading among the residents of {@organisation.name}?</:subtitle>
      </.header>

      <section aria-labelledby="weeks-heading">
        <h2 id="weeks-heading">New cases of each condition</h2>
        <p>
          The conditions that started in each of the last {@weeks} weeks, and the cases that go on
          now. The more new cases of a condition in a week, the stronger the colour. A condition
          starts with a diagnosis in the journal.
        </p>
        <figure data-chart>
          <.heat_table
            id="conditions"
            variant="numbers"
            summary={summary(@counts, @mondays)}
            columns={columns(@mondays)}
            rows={rows(@counts)}
            corner="Condition"
          />
        </figure>
        <p>
          <.link navigate={~p"/o/#{@organisation.short_name}/residents/conditions"}>
            Each condition of each resident
          </.link>
        </p>
      </section>
    </Layouts.app>
    """
  end
end
