defmodule RescordWeb.StockInsightsLive do
  @moduledoc """
  The days left of the stock of each item, at
  `/o/<short name>/insights/stock` (ADR 0123): when will we run out of
  each item?

  A time line of the next 90 days has a row for each item that was used or
  discarded in the last 30 days, the soonest to run out first: a link to
  the item, a note in words, and a bar from today to the day when its
  stock runs out at that rate, dashed when it lasts past the 90 days. The
  items with no use are named below it. The page of an item has the chart
  of its stock over time.

  Each member can open the page: it reads the inventory as that member.
  """

  use RescordWeb, :live_view

  import RescordWeb.ChartComponents

  alias Rescord.{Accounts, Inventory}
  alias RescordWeb.{Chart, InventoryWords, Locale}

  @days 90

  @impl true
  def mount(_params, _session, socket) do
    options = [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
    today = Accounts.today(socket.assigns.organisation)
    {:ok, stock} = Inventory.stock(options)
    {:ok, used} = Inventory.use_by_item(today, options)

    {lasting, idle} =
      stock
      |> Enum.map(fn stock ->
        usable = Decimal.sub(stock.level, stock.expired)
        use = Map.get(used, stock.item.id, Decimal.new(0))
        %{item: stock.item, usable: usable, used: use, days: Inventory.days_left(usable, use)}
      end)
      |> Enum.split_with(& &1.days)

    {:ok,
     assign(socket,
       page_title: "Stock and days left",
       today: today,
       last: Date.add(today, @days - 1),
       lasting: Enum.sort_by(lasting, &{&1.days, String.downcase(&1.item.name)}),
       idle: idle
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp ticks(today, last) do
    for {date, x} <- Chart.months(today, last), do: %{x: x, label: Locale.short_month(date)}
  end

  defp rows(lasting, organisation, today, last) do
    for row <- lasting do
      runs_out = Date.add(today, row.days)

      %{
        id: "item-#{row.item.id}",
        name: row.item.name,
        href: ~p"/o/#{organisation.short_name}/inventory/#{row.item.id}",
        note: note(row, runs_out),
        bars: [
          Map.put(
            Chart.span(today, Enum.min([runs_out, last], Date), today, last),
            :open,
            Date.after?(runs_out, last)
          )
        ]
      }
    end
  end

  defp note(%{days: 0} = row, _runs_out),
    do: "#{InventoryWords.quantity(row.usable, row.item)} in stock: it has run out."

  defp note(row, runs_out) do
    "#{InventoryWords.quantity(row.usable, row.item)} in stock, and " <>
      "#{InventoryWords.quantity(row.used, row.item)} used or discarded in 30 days: about " <>
      "#{Locale.count(row.days, "day", "days")} left, to #{Locale.date(runs_out)}."
  end

  defp summary([], _today), do: "No item was used or discarded in the last 30 days."

  defp summary(lasting, today) do
    soon = Enum.count(lasting, &(&1.days <= 14))
    first = hd(lasting)

    "#{Locale.count(length(lasting), "item was", "items were")} used or discarded in the last " <>
      "30 days, and #{Locale.count(soon, "runs", "run")} out in the next 14 days at that rate. " <>
      "#{first.item.name} runs out first, on #{Locale.date(Date.add(today, first.days))}."
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
        Stock and days left
        <:subtitle>When will {@organisation.name} run out of each item?</:subtitle>
      </.header>

      <section aria-labelledby="left-heading">
        <h2 id="left-heading">Days left of each item</h2>
        <p>
          A bar from today to the day when the stock of an item that has not expired runs out, at
          the rate of what members used or discarded of it in the last 30 days, the soonest first.
          A bar that lasts past {Locale.date(@last)} is dashed. The page of an item has its stock
          over time.
        </p>
        <.timeline
          id="left"
          label="The items"
          summary={summary(@lasting, @today)}
          ticks={ticks(@today, @last)}
          rows={rows(@lasting, @organisation, @today, @last)}
        />
        <p :if={@idle != []}>
          With no use in the last 30 days: {Locale.list(Enum.map(@idle, & &1.item.name))}.
        </p>
      </section>
    </Layouts.app>
    """
  end
end
