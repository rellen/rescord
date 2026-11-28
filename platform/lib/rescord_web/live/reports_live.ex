defmodule RescordWeb.ReportsLive do
  @moduledoc """
  The reports of an organisation, at `/o/<short name>/reports` (ADR 0076):
  documents for paper, each a PDF.

  Each form is a plain `GET` to `RescordWeb.ReportController`, because a
  page of LiveView cannot send a file. The reports of one resident, its
  record and its cage card, start from the page of that resident.
  """

  use RescordWeb, :live_view

  alias Rescord.Accounts

  @impl true
  def mount(_params, _session, socket) do
    today = Accounts.today(socket.assigns.organisation)

    {:ok,
     assign(socket,
       page_title: "Reports",
       today: Date.to_iso8601(today),
       month_start: Date.to_iso8601(Date.beginning_of_month(today)),
       periods: periods(today)
     )}
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The periods that a person asks for most, each as a link.
  defp periods(today) do
    last_month_end = Date.add(Date.beginning_of_month(today), -1)

    [
      {"Last month", Date.beginning_of_month(last_month_end), last_month_end},
      {"This year so far", Date.new!(today.year, 1, 1), today},
      {"Last year", Date.new!(today.year - 1, 1, 1), Date.new!(today.year - 1, 12, 31)}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:reports}
    >
      <.header>
        Reports
        <:subtitle>Documents of {@organisation.name} for paper, each a PDF</:subtitle>
      </.header>

      <section aria-labelledby="register-heading">
        <h2 id="register-heading">Register of residents</h2>
        <p>
          Each resident in care on one day, with its facts, its place and the identifiers that it has.
        </p>
        <form id="register" action={~p"/o/#{@organisation.short_name}/reports/register.pdf"}>
          <.input
            id="register-on"
            name="on"
            type="date"
            label="In care on"
            value={@today}
            max={@today}
            required
          />
          <button type="submit">Make the register</button>
        </form>
      </section>

      <section aria-labelledby="movements-heading">
        <h2 id="movements-heading">Arrivals and departures</h2>
        <p>
          The residents that arrived and the ones that left in a period, with the totals by
          kind and by species.
        </p>
        <form id="movements" action={~p"/o/#{@organisation.short_name}/reports/movements.pdf"}>
          <.input
            id="movements-from"
            name="from"
            type="date"
            label="From"
            value={@month_start}
            max={@today}
            required
          />
          <.input
            id="movements-to"
            name="to"
            type="date"
            label="To"
            value={@today}
            max={@today}
            required
          />
          <button type="submit">Make the report</button>
        </form>
        <ul id="movements-periods">
          <li :for={{words, from, to} <- @periods}>
            <a href={
              ~p"/o/#{@organisation.short_name}/reports/movements.pdf?#{[from: Date.to_iso8601(from), to: Date.to_iso8601(to)]}"
            }>
              {words}
            </a>
          </li>
        </ul>
      </section>

      <section aria-labelledby="tasks-heading">
        <h2 id="tasks-heading">Tasks of a day</h2>
        <p>The tasks that are due on one day, each with a box to tick, and the late ones.</p>
        <form id="task-sheet" action={~p"/o/#{@organisation.short_name}/reports/tasks.pdf"}>
          <.input id="task-sheet-on" name="on" type="date" label="Day" value={@today} required />
          <button type="submit">Make the sheet</button>
        </form>
      </section>

      <section aria-labelledby="stock-heading">
        <h2 id="stock-heading">Stock</h2>
        <p>
          The stock of each item with its lots, what needs somebody first, and a column for
          a count.
        </p>
        <p>
          <a id="stock" href={~p"/o/#{@organisation.short_name}/reports/stock.pdf"}>
            Make the stock report
          </a>
        </p>
      </section>

      <section aria-labelledby="housing-heading">
        <h2 id="housing-heading">Housing</h2>
        <p>Each location with who lives there now, for a walk through the refuge.</p>
        <p>
          <a id="housing" href={~p"/o/#{@organisation.short_name}/reports/housing.pdf"}>
            Make the housing report
          </a>
        </p>
      </section>

      <section aria-labelledby="expenses-heading">
        <h2 id="expenses-heading">Expenses</h2>
        <p>
          The expenses of a period that you can read, with their sums by state and by
          category, and what the organisation owes to each member.
        </p>
        <form id="expenses" action={~p"/o/#{@organisation.short_name}/reports/expenses.pdf"}>
          <.input
            id="expenses-from"
            name="from"
            type="date"
            label="From"
            value={@month_start}
            max={@today}
            required
          />
          <.input id="expenses-to" name="to" type="date" label="To" value={@today} required />
          <button type="submit">Make the report</button>
        </form>
        <ul id="expenses-periods">
          <li :for={{words, from, to} <- @periods}>
            <a href={
              ~p"/o/#{@organisation.short_name}/reports/expenses.pdf?#{[from: Date.to_iso8601(from), to: Date.to_iso8601(to)]}"
            }>
              {words}
            </a>
          </li>
        </ul>
      </section>

      <section aria-labelledby="resident-heading">
        <h2 id="resident-heading">One resident</h2>
        <p>
          The record of a resident, with its medical history, and its cage card start from
          the page of that resident.
        </p>
        <p>
          <.link navigate={~p"/o/#{@organisation.short_name}/residents"}>Choose a resident</.link>
        </p>
      </section>
    </Layouts.app>
    """
  end
end
