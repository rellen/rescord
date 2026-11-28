defmodule RescordWeb.LengthsInsightsLive do
  @moduledoc """
  How long the residents stay, and how their stays end, at
  `/o/<short name>/insights/lengths` (ADR 0124).

  For each way of arrival with 10 stays or more, a step line of the share
  of the residents still in care against the days since their arrival
  (Kaplan and Meier, `Rescord.Residents.Survival`), with a rule at a half.
  A table has the days by which a quarter, a half and three quarters of
  each group had left, and a table counts how the stays ended by how they
  began.

  Each member can open the page: it reads the residents as that member.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents

  alias Rescord.{Accounts, Residents}
  alias RescordWeb.{Chart, JournalWords, Locale, ResidentWords}

  # A group with fewer stays than this draws no line.
  @least 10

  # A day since the arrival is an instant after this one, so that
  # `line_chart/1` places it on its scale of time.
  @epoch ~U[2000-01-01 12:00:00Z]

  @impl true
  def mount(_params, _session, socket) do
    today = Accounts.today(socket.assigns.organisation)

    {:ok, stays} =
      Residents.stays(actor: socket.assigns.current_user, tenant: socket.assigns.organisation)

    stays =
      for stay <- stays, not Date.after?(stay.arrived_on, today) do
        Map.put(stay, :days, Date.diff(stay.departed_on || today, stay.arrived_on))
      end

    groups =
      for kind <- ResidentWords.values(:arrival),
          of_kind = Enum.filter(stays, &(&1.arrival_kind == kind)),
          of_kind != [] do
        group(kind, of_kind)
      end

    {:ok,
     assign(socket,
       page_title: "Lengths of stay",
       groups: groups,
       scale: scale(groups),
       outcomes: ResidentWords.values(:departure),
       least: @least
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp group(kind, stays) do
    lengths = Enum.map(stays, &{&1.days, not is_nil(&1.departed_on)})

    %{
      kind: kind,
      count: length(stays),
      in_care: Enum.count(stays, &is_nil(&1.departed_on)),
      ended: Enum.frequencies_by(stays, & &1.departure_kind),
      longest: stays |> Enum.map(& &1.days) |> Enum.max(),
      curve: Residents.stay_curve(lengths),
      quarter: Residents.stay_day_when(lengths, {3, 4}),
      half: Residents.stay_day_when(lengths, {1, 2}),
      three_quarters: Residents.stay_day_when(lengths, {1, 4})
    }
  end

  defp drawn?(group), do: group.count >= @least

  defp at(days), do: DateTime.add(@epoch, days, :day)

  defp points(group) do
    steps =
      for {days, share} <- group.curve do
        percent = Decimal.mult(share, 100)

        %{
          id: "#{group.kind}-#{days}",
          at: at(days),
          value: percent,
          label: "Day #{days}: #{JournalWords.number(Decimal.round(percent, 0))}% in care"
        }
      end

    # The line goes on to the longest stay, which may go on.
    {last_day, last_share} = List.last(group.curve)

    if group.longest > last_day do
      percent = Decimal.mult(last_share, 100)

      steps ++
        [
          %{
            id: "#{group.kind}-end",
            at: at(group.longest),
            value: percent,
            label:
              "Day #{group.longest}: #{JournalWords.number(Decimal.round(percent, 0))}% in care"
          }
        ]
    else
      steps
    end
  end

  # One scale for each line, so that the lines compare.
  defp scale(groups) do
    drawn = Enum.filter(groups, &drawn?/1)
    anchors = [%{at: @epoch, value: Decimal.new(0)}, %{at: @epoch, value: Decimal.new(100)}]
    Chart.scale(Enum.flat_map(drawn, &points/1) ++ anchors)
  end

  defp longest(groups),
    do: groups |> Enum.filter(&drawn?/1) |> Enum.map(& &1.longest) |> Enum.max()

  defp summary(group) do
    base =
      "#{Locale.count(group.count, "resident", "residents")}, and #{group.in_care} in care now."

    case group.half do
      nil -> base <> " Fewer than half have left."
      day -> base <> " Half had left by day #{JournalWords.number(day)}."
    end
  end

  defp day(nil), do: "Not yet"
  defp day(day), do: "Day #{JournalWords.number(day)}"

  defp percent(tick), do: "#{JournalWords.number(tick)}%"

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
        Lengths of stay
        <:subtitle>
          How long do residents of {@organisation.name} stay, and how do stays end?
        </:subtitle>
      </.header>

      <p :if={@groups == []}>No resident has arrived yet.</p>

      <section :if={@groups != []} aria-labelledby="curves-heading">
        <h2 id="curves-heading">Still in care, by the days since arrival</h2>
        <p>
          For each way of arrival, the share of its residents still in care on each day after they
          arrived. A resident still in care counts up to today. The dashed line is a half. A way of
          arrival with fewer than {@least} residents has no line.
        </p>
        <section :for={group <- @groups} aria-labelledby={"curve-#{group.kind}-heading"}>
          <h3 id={"curve-#{group.kind}-heading"}>{ResidentWords.arrival(group.kind)}</h3>
          <.line_chart
            :if={drawn?(group)}
            id={"curve-#{group.kind}"}
            title={"The share of the residents of #{ResidentWords.arrival(group.kind)} still in care, by the days since arrival"}
            summary={summary(group)}
            points={points(group)}
            scale={@scale}
            rules={[Decimal.new(50)]}
            tick={&percent/1}
            step
            from="Day 0"
            to={"Day #{JournalWords.number(longest(@groups))}"}
          />
          <p :if={!drawn?(group)}>
            {Locale.count(group.count, "resident", "residents")}: too few for a line.
          </p>
        </section>

        <table id="lengths">
          <caption>The day by which each part of the residents of a way of arrival had left</caption>
          <thead>
            <tr>
              <th scope="col">Arrival</th>
              <th scope="col">Residents</th>
              <th scope="col">In care now</th>
              <th scope="col">A quarter had left</th>
              <th scope="col">Half had left</th>
              <th scope="col">Three quarters had left</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={group <- @groups}>
              <th scope="row">{ResidentWords.arrival(group.kind)}</th>
              <td data-label="Residents">{JournalWords.number(group.count)}</td>
              <td data-label="In care now">{JournalWords.number(group.in_care)}</td>
              <td data-label="A quarter had left">{day(group.quarter)}</td>
              <td data-label="Half had left">{day(group.half)}</td>
              <td data-label="Three quarters had left">{day(group.three_quarters)}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section :if={@groups != []} aria-labelledby="outcomes-heading">
        <h2 id="outcomes-heading">How stays ended</h2>
        <table id="outcomes">
          <caption>The stays of each way of arrival, by how they ended</caption>
          <thead>
            <tr>
              <th scope="col">Arrival</th>
              <th :for={outcome <- @outcomes} scope="col">{ResidentWords.departure(outcome)}</th>
              <th scope="col">In care now</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={group <- @groups}>
              <th scope="row">{ResidentWords.arrival(group.kind)}</th>
              <td :for={outcome <- @outcomes} data-label={ResidentWords.departure(outcome)}>
                {JournalWords.number(Map.get(group.ended, outcome, 0))}
              </td>
              <td data-label="In care now">{JournalWords.number(group.in_care)}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end
end
