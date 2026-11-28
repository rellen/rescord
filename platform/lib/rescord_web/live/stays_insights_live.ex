defmodule RescordWeb.StaysInsightsLive do
  @moduledoc """
  The stays of the residents over a year, at
  `/o/<short name>/insights/stays` (ADR 0121): who came when, and who has
  been here longest?

  A time line has a row for each resident in care on a day of the last 12
  months: the name, which links to the resident, how the stay began, its
  days and how it ended, and a bar from the arrival to the departure, or
  dashed to today for a stay that goes on. A species narrows it, and the
  rows are in the order of the arrivals or of the lengths.

  Each member can open the page: it reads the residents as that member. It
  reads only the values that it knows from what the browser sends, and
  makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents
  import RescordWeb.InsightComponents

  alias Rescord.{Accounts, Lists, Residents}
  alias RescordWeb.{Chart, Locale, ResidentWords}

  @days 365

  @orders [{"Arrival, the first first", "arrival"}, {"Length, the longest first", "length"}]

  @impl true
  def mount(_params, _session, socket) do
    species =
      case Lists.values(:species, options(socket)) do
        {:ok, values} -> Enum.map(values, &{to_string(&1.label), &1.id})
        {:error, _error} -> []
      end

    {:ok,
     socket
     |> assign(page_title: "Stays", species: species, orders: @orders)
     |> assign_stays(nil, "arrival")}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_stays(socket, species_id, order) do
    today = Accounts.today(socket.assigns.organisation)
    first = Date.add(today, -(@days - 1))
    {:ok, stays} = Residents.stays([species: species_id] ++ options(socket))

    stays =
      stays
      |> Enum.filter(&(is_nil(&1.departed_on) or Date.compare(&1.departed_on, first) != :lt))
      |> Enum.filter(&(Date.compare(&1.arrived_on, today) != :gt))
      |> Enum.map(&Map.put(&1, :days, Date.diff(&1.departed_on || today, &1.arrived_on)))
      |> sort(order)

    assign(socket,
      today: today,
      first: first,
      stays: stays,
      form: to_form(%{"species_id" => species_id || "", "order" => order}, as: :stays)
    )
  end

  # The stays come in the order of the arrivals.
  defp sort(stays, "length"), do: Enum.sort_by(stays, & &1.days, :desc)
  defp sort(stays, _arrival), do: stays

  @impl true
  def handle_event("view", %{"stays" => fields}, socket) when is_map(fields) do
    # Only a species of the list of this organisation, and an order of the
    # page.
    species_id =
      Enum.find_value(socket.assigns.species, fn {_label, id} ->
        if id == fields["species_id"], do: id
      end)

    order =
      Enum.find_value(@orders, "arrival", fn {_label, value} ->
        if value == fields["order"], do: value
      end)

    {:noreply, assign_stays(socket, species_id, order)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp ticks(first, last) do
    # A phone shows the month of each quarter.
    for {date, x} <- Chart.months(first, last),
        do: %{x: x, label: Locale.short_month(date), minor: rem(date.month, 3) != 1}
  end

  defp rows(stays, organisation, first, today) do
    for stay <- stays do
      %{
        id: "stay-#{stay.id}",
        name: name(stay),
        href: ~p"/o/#{organisation.short_name}/residents/#{stay.id}",
        note: note(stay),
        bars: [
          Map.put(
            Chart.span(stay.arrived_on, stay.departed_on || today, first, today),
            :open,
            is_nil(stay.departed_on)
          )
        ]
      }
    end
  end

  defp name(%{name: nil}), do: "A resident with no name"
  defp name(%{name: name}), do: to_string(name)

  defp note(%{departed_on: nil} = stay) do
    "#{ResidentWords.arrival(stay.arrival_kind)}, from #{Locale.date(stay.arrived_on)}, " <>
      "#{Locale.count(stay.days, "day", "days")}, in care"
  end

  defp note(stay) do
    "#{ResidentWords.arrival(stay.arrival_kind)}, #{Locale.date(stay.arrived_on)} to " <>
      "#{Locale.date(stay.departed_on)}, #{Locale.count(stay.days, "day", "days")}, " <>
      "#{ResidentWords.departure(stay.departure_kind)}"
  end

  defp summary([]), do: "No resident was in care in the last 12 months."

  defp summary(stays) do
    going_on = Enum.filter(stays, &is_nil(&1.departed_on))

    base =
      "#{Locale.count(length(stays), "resident was", "residents were")} in care in the last " <>
        "12 months, and #{Locale.count(length(going_on), "stay goes", "stays go")} on."

    case going_on do
      [] ->
        base

      going_on ->
        longest = Enum.max_by(going_on, & &1.days)

        base <>
          " The longest that goes on is of #{name(longest)}: #{Locale.count(longest.days, "day", "days")}."
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
        Stays
        <:subtitle>Who came to {@organisation.name} when, and who has been here longest?</:subtitle>
      </.header>

      <.form for={@form} id="stays-view" phx-change="view" phx-submit="view">
        <.input
          :if={@species != []}
          field={@form[:species_id]}
          type="select"
          label="Species"
          prompt="Each species"
          options={@species}
        />
        <.input field={@form[:order]} type="select" label="Order" options={@orders} />
      </.form>

      <section aria-labelledby="stays-heading">
        <h2 id="stays-heading">The stays of the last 12 months</h2>
        <p>
          A bar for each resident in care on a day from {Locale.date(@first)} to today, from the
          arrival to the departure. A stay that goes on is dashed to today.
        </p>
        <.key items={[{"up", "A stay that ended"}, {"open", "A stay that goes on"}]} />
        <.timeline
          id="stays"
          label="The stays"
          summary={summary(@stays)}
          ticks={ticks(@first, @today)}
          rows={rows(@stays, @organisation, @first, @today)}
        />
      </section>
    </Layouts.app>
    """
  end
end
