defmodule RescordWeb.ReportsLive do
  @moduledoc """
  The reports of an organisation, at `/o/<short name>/reports` (ADR 0076):
  documents for paper, each a PDF. It starts with the pages of insights,
  charts on the screen (ADR 0116).

  Each form is a plain `GET` to `RescordWeb.ReportController`, because a
  page of LiveView cannot send a file. The reports of one resident, its
  record and its cage card, start from the page of that resident.

  The control "Paper" at the top chooses the paper of each report of the
  page (ADR 0093): the one of the organisation at first. The choice is in
  the address, as `paper`, and each form and each link here sends it.
  """

  use RescordWeb, :live_view

  import RescordWeb.InsightComponents, only: [insights: 1]
  import RescordWeb.ReportComponents, only: [paper_control: 1]

  alias Rescord.Accounts
  alias RescordWeb.ReportWords

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

  # The paper of the address, or the one of the organisation.
  @impl true
  def handle_params(params, _uri, socket) do
    paper = Accounts.paper_size(params["paper"]) || socket.assigns.organisation.paper_size
    {:noreply, assign(socket, paper: paper, paper_value: Atom.to_string(paper))}
  end

  @impl true
  def handle_event("paper", %{"paper" => text}, socket) do
    organisation = socket.assigns.organisation

    case Accounts.paper_size(text) do
      nil ->
        {:noreply, socket}

      paper ->
        {:noreply,
         push_patch(socket, to: ~p"/o/#{organisation.short_name}/reports?#{[paper: paper]}")}
    end
  end

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
      inbox={@inbox}
      ruby={@ruby?}
      section={:reports}
    >
      <.header icon={Icons.section(:reports)}>
        Reports
        <:subtitle>
          Charts of {@organisation.name} on the screen, and documents for paper, each a PDF
        </:subtitle>
      </.header>

      <section aria-labelledby="insights-heading">
        <h2 id="insights-heading"><.icon name={Icons.section(:insights)} /> Insights</h2>
        <.insights organisation={@organisation} />
      </section>

      <section aria-labelledby="paper-heading">
        <h2 id="paper-heading"><.icon name="printer" /> Paper</h2>
        <form id="paper" action={~p"/o/#{@organisation.short_name}/reports"} phx-change="paper">
          <.paper_control id="paper-size" value={@paper} />
          <noscript><button type="submit">Use this paper</button></noscript>
        </form>
        <p>
          Each report of this page is on {ReportWords.paper_name(@paper)} paper. The settings
          of {@organisation.name} say which paper is chosen at first.
        </p>
      </section>

      <section aria-labelledby="register-heading">
        <h2 id="register-heading">
          <.icon name={Icons.section(:residents)} /> Register of residents
        </h2>
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
          <input type="hidden" name="paper" value={@paper_value} />
          <footer><button type="submit">Make the register</button></footer>
        </form>
      </section>

      <section aria-labelledby="movements-heading">
        <h2 id="movements-heading"><.icon name="door-in" /> Arrivals and departures</h2>
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
          <input type="hidden" name="paper" value={@paper_value} />
          <footer><button type="submit">Make the report</button></footer>
        </form>
        <ul id="movements-periods">
          <li :for={{words, from, to} <- @periods}>
            <a href={
              ~p"/o/#{@organisation.short_name}/reports/movements.pdf?#{[from: Date.to_iso8601(from), to: Date.to_iso8601(to), paper: @paper_value]}"
            }>
              {words}
            </a>
          </li>
        </ul>
      </section>

      <section aria-labelledby="tasks-heading">
        <h2 id="tasks-heading"><.icon name={Icons.section(:tasks)} /> Tasks of a day</h2>
        <p>The tasks that are due on one day, each with a box to tick, and the overdue ones.</p>
        <form id="task-sheet" action={~p"/o/#{@organisation.short_name}/reports/tasks.pdf"}>
          <.input id="task-sheet-on" name="on" type="date" label="Day" value={@today} required />
          <input type="hidden" name="paper" value={@paper_value} />
          <footer><button type="submit">Make the sheet</button></footer>
        </form>
      </section>

      <section aria-labelledby="stock-heading">
        <h2 id="stock-heading"><.icon name={Icons.section(:inventory)} /> Stock</h2>
        <p>
          The stock of each item and its lots: first the items to order, to count or that
          expire soon, then the others, with a column to write a count.
        </p>
        <p>
          <a
            id="stock"
            href={~p"/o/#{@organisation.short_name}/reports/stock.pdf?#{[paper: @paper_value]}"}
          >
            Make the stock report
          </a>
        </p>
      </section>

      <section aria-labelledby="housing-heading">
        <h2 id="housing-heading"><.icon name={Icons.section(:housing)} /> Housing</h2>
        <p>Each location with who lives there now, for a walk through the refuge.</p>
        <p>
          <a
            id="housing"
            href={~p"/o/#{@organisation.short_name}/reports/housing.pdf?#{[paper: @paper_value]}"}
          >
            Make the housing report
          </a>
        </p>
      </section>

      <section aria-labelledby="expenses-heading">
        <h2 id="expenses-heading"><.icon name={Icons.section(:expenses)} /> Expenses</h2>
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
          <input type="hidden" name="paper" value={@paper_value} />
          <footer><button type="submit">Make the report</button></footer>
        </form>
        <ul id="expenses-periods">
          <li :for={{words, from, to} <- @periods}>
            <a href={
              ~p"/o/#{@organisation.short_name}/reports/expenses.pdf?#{[from: Date.to_iso8601(from), to: Date.to_iso8601(to), paper: @paper_value]}"
            }>
              {words}
            </a>
          </li>
        </ul>
      </section>

      <section aria-labelledby="resident-heading">
        <h2 id="resident-heading"><.icon name={Icons.section(:residents)} /> One resident</h2>
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
