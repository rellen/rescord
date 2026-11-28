defmodule RescordWeb.ExpensesLive do
  @moduledoc """
  The expenses of an organisation, at `/o/<short name>/expenses`
  (ADR 0082).

  The page shows three sums, then the expenses that the person reads: each
  one for a person who manages the expenses, and their own for each other
  person. The list has a search, filters and a sort. `?resident=<id>` holds
  the list to the expenses of one resident.

  The filters are in the address of the page (`Cinder.UrlSync`), so the
  link to the CSV file carries them, and the file holds what the list
  holds.

  The page reads the sums and the list again when an expense changes
  (ADR 0096), so a decision of another person shows at once.
  """

  use RescordWeb, :live_view
  use Cinder.UrlSync

  import RescordWeb.ExpenseComponents

  alias Rescord.{Accounts, Expenses, Lists, Residents}
  alias RescordWeb.{ExpenseWords, ResidentWords}

  # What the address holds of the list, and what the CSV file reads.
  @limits ~w(search status category_id paid_by incurred_on resident)

  @impl true
  def mount(_params, _session, socket) do
    options = options(socket)
    role = socket.assigns.role
    {:ok, figures} = Expenses.figures(options)
    {:ok, members} = Accounts.members([load: [:email]] ++ options)
    {:ok, categories} = Lists.values(:expense_category, options)

    {:ok,
     socket
     |> LiveChanges.listen([Expenses], &read_again/1)
     |> assign(
       page_title: "Expenses",
       can_manage?: Expenses.role_can?(role, :expense, :approve),
       can_record?: Expenses.role_can?(role, :expense, :submit),
       figures: figures,
       people: Map.new(members, &{&1.user_id, to_string(&1.email)}),
       categories: for(value <- categories, do: {to_string(value.label), value.id}),
       resident: nil,
       limits: %{},
       period: period(%{}, socket.assigns.organisation)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    limits =
      for {key, value} <- params, key in @limits, is_binary(value), into: %{}, do: {key, value}

    {:noreply,
     assign(socket,
       resident: resident(socket, params["resident"]),
       limits: limits,
       period: period(limits, socket.assigns.organisation)
     )}
  end

  # The first and the last day of the report as PDF: the dates of the filter
  # when it has both, or else this month until today.
  defp period(limits, organisation) do
    today = Accounts.today(organisation)

    with text when is_binary(text) <- limits["incurred_on"],
         [from, to] <- String.split(text, ","),
         {:ok, from} <- Date.from_iso8601(from),
         {:ok, to} <- Date.from_iso8601(to),
         true <- Date.compare(from, to) != :gt do
      {from, to}
    else
      _no_period -> {Date.beginning_of_month(today), today}
    end
  end

  # After a change of another person (ADR 0096): the sums, and the rows of
  # the list, which stay on the page while Cinder reads.
  defp read_again(socket) do
    {:ok, figures} = Expenses.figures(options(socket))

    socket
    |> assign(figures: figures)
    |> Cinder.refresh_table("expenses", silent: true)
  end

  defp resident(socket, id) when is_binary(id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = resident} <- Residents.resident(id, [load: [:name]] ++ options(socket)) do
      resident
    else
      _no_resident -> nil
    end
  end

  defp resident(_socket, _none), do: nil

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # Ignore an event that this page does not know.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # The search of the list looks in what the expense was for, and in who
  # was paid.
  defp search(query, _columns, words), do: Expenses.limit_to(query, %{search: words})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:expenses}
    >
      <.header>
        Expenses
        <:subtitle :if={@can_manage?}>What {@organisation.name} and its members paid</:subtitle>
        <:subtitle :if={!@can_manage?}>
          The expenses that you recorded, and those that {@organisation.name} pays back to you
        </:subtitle>
        <:actions>
          <.link
            :if={@can_record?}
            navigate={~p"/o/#{@organisation.short_name}/expenses/new"}
            data-variant="primary"
          >
            Record an expense
          </.link>
        </:actions>
      </.header>

      <.figures figures={@figures} manage?={@can_manage?} currency={@organisation.currency} />

      <p :if={@resident} role="status">
        Only the expenses for <.link navigate={
          ~p"/o/#{@organisation.short_name}/residents/#{@resident.id}"
        }>{@resident.name || "a resident with no name"}</.link>.
        <.link navigate={~p"/o/#{@organisation.short_name}/expenses"}>Show each expense</.link>
      </p>

      <Cinder.collection
        id="expenses"
        query={
          Expenses.list_query(%{resident_id: @resident && @resident.id},
            actor: @current_user,
            tenant: @organisation
          )
        }
        actor={@current_user}
        tenant={@organisation}
        url_state={@url_state}
        search={[label: "Search", placeholder: "What it was for, or who was paid", fn: &search/3]}
        empty_message="No expense is in this list."
      >
        <:col :let={expense} field="description" label="Expense" sort search>
          <.link navigate={~p"/o/#{@organisation.short_name}/expenses/#{expense.id}"}>
            {expense.description}
          </.link>
          <small>
            {expense.payee}<span :if={expense.receipt_count > 0}> · <.icon name="paper-clip" /> {ExpenseWords.count(
              expense.receipt_count,
              "receipt"
            )}</span>
          </small>
        </:col>
        <:col :let={expense} field="incurred_on" label="Date" sort filter={[type: :date_range]}>
          <span data-label="Date">{ResidentWords.date(expense.incurred_on)}</span>
        </:col>
        <:col
          :let={expense}
          field="category_id"
          label="Category"
          filter={[type: :select, prompt: "Any category", options: @categories]}
        >
          <span data-label="Category">{expense.category && expense.category.label}</span>
        </:col>
        <:col
          :let={expense}
          field="paid_by"
          label="Paid by"
          filter={[
            type: :select,
            prompt: "Anybody",
            options: [{"A member", "member"}, {@organisation.name, "organisation"}]
          ]}
        >
          <span data-label="Paid by">{ExpenseWords.paid_by(expense, @organisation, @people)}</span>
        </:col>
        <:col :let={expense} field="amount" label="Amount" sort>
          <span data-money data-label="Amount">{ExpenseWords.money(expense.amount)}</span>
        </:col>
        <:col
          :let={expense}
          field="status"
          label="State"
          filter={[type: :select, prompt: "Any state", options: ExpenseWords.status_options()]}
        >
          <.state kind={ExpenseWords.status_kind(expense.status)}>
            {ExpenseWords.status(expense.status)}
          </.state>
        </:col>
      </Cinder.collection>

      <p data-downloads>
        <a
          href={~p"/o/#{@organisation.short_name}/expenses.csv?#{@limits}"}
          data-variant="secondary"
          download
        >
          These expenses as CSV
        </a>
        <a
          id="expenses-pdf"
          href={
            ~p"/o/#{@organisation.short_name}/reports/expenses.pdf?#{[from: Date.to_iso8601(elem(@period, 0)), to: Date.to_iso8601(elem(@period, 1))]}"
          }
          data-variant="secondary"
        >
          Report of {ResidentWords.date(elem(@period, 0))} to {ResidentWords.date(elem(@period, 1))} as PDF
        </a>
      </p>
    </Layouts.app>
    """
  end
end
