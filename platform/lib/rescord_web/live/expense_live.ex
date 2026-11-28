defmodule RescordWeb.ExpenseLive do
  @moduledoc """
  One expense, at `/o/<short name>/expenses/<id>` (ADR 0082).

  The page shows the amount and the state, the facts, the receipts, and
  what happened to the expense, the newest first. A person who manages the
  expenses approves the expense or declines it with a reason, records that
  the organisation paid the member back, and opens a decision again. The
  person who recorded the expense changes it or withdraws it while it waits
  or after it was declined, and adds a receipt at any time.

  The page shows a control only where `Rescord.Expenses.can?/4` says that
  the action would work. The policy of each resource decides when an action
  runs.
  """

  use RescordWeb, :live_view

  import RescordWeb.ExpenseComponents

  alias Rescord.{Accounts, Expenses}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    options = options(socket)

    with true <- is_binary(id),
         {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = expense} <- Expenses.expense(id, [load: Expenses.summary()] ++ options),
         {:ok, receipts} <- Expenses.receipts_of(expense.id, options),
         {:ok, events} <- Expenses.history(expense.id, options) do
      {:ok, members} = Accounts.members([load: [:email]] ++ options)
      role = socket.assigns.role
      user = socket.assigns.current_user
      can? = &Expenses.can?(role, user, expense, &1)

      {:ok,
       socket
       |> assign(
         page_title: expense.description,
         expense: expense,
         receipts: receipts,
         events: events,
         people: Map.new(members, &{&1.user_id, to_string(&1.email)}),
         problems: [],
         problems_at: :page,
         max_date: Date.to_iso8601(Accounts.today(socket.assigns.organisation)),
         removable:
           for(
             receipt <- receipts,
             Expenses.can_take_off?(role, user, expense, receipt),
             into: MapSet.new(),
             do: receipt.id
           ),
         can: %{
           revise?: can?.(:revise),
           withdraw?: can?.(:withdraw),
           approve?: can?.(:approve),
           decline?: can?.(:decline),
           reimburse?: can?.(:reimburse),
           reopen?: can?.(:reopen)
         }
       )
       |> allow_receipts()}
    else
      _no_expense ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such expense.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/expenses")}
    end
  end

  defp allow_receipts(socket) do
    if Expenses.role_can?(socket.assigns.role, :receipt, :attach) do
      allow_upload(socket, :receipts,
        accept: ~w(.jpg .jpeg .png .gif .webp .pdf),
        max_entries: Expenses.max_receipts(),
        max_file_size: Expenses.max_receipt_size()
      )
    else
      socket
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp path(socket),
    do: ~p"/o/#{socket.assigns.organisation.short_name}/expenses/#{socket.assigns.expense.id}"

  @impl true
  def handle_event("choose", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_receipt", %{"ref" => ref}, socket) when is_binary(ref) do
    {:noreply, cancel_upload(socket, :receipts, ref)}
  end

  def handle_event("approve", _params, socket) do
    socket.assigns.expense
    |> Expenses.approve_expense(options(socket))
    |> after_write(socket, "The expense is approved.")
  end

  def handle_event("decline", %{"decline" => %{"reason" => reason}}, socket) do
    socket.assigns.expense
    |> Expenses.decline_expense(non_blank(reason), options(socket))
    |> after_write(socket, "The expense is declined.")
  end

  def handle_event("reimburse", %{"reimburse" => fields}, socket) when is_map(fields) do
    socket.assigns.expense
    |> Expenses.reimburse_expense(
      %{
        reimbursed_on: non_blank(fields["on"]),
        reimbursement_reference: non_blank(fields["reference"])
      },
      options(socket)
    )
    |> after_write(socket, "The payment is recorded.")
  end

  def handle_event("reopen", _params, socket) do
    socket.assigns.expense
    |> Expenses.reopen_expense(options(socket))
    |> after_write(socket, "The expense waits for a decision again.")
  end

  def handle_event("withdraw", _params, socket) do
    case Expenses.withdraw_expense(socket.assigns.expense, options(socket)) do
      {:error, error} ->
        {:noreply, problems(socket, :page, Accounts.error_messages(error))}

      _done ->
        {:noreply,
         socket
         |> put_flash(:info, "The expense is withdrawn.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/expenses")}
    end
  end

  def handle_event("attach", _params, socket) do
    if socket.assigns[:uploads][:receipts] do
      results =
        consume_uploaded_entries(socket, :receipts, fn %{path: path}, entry ->
          result =
            Expenses.attach_receipt(
              %{
                expense_id: socket.assigns.expense.id,
                name: entry.client_name,
                content: File.read!(path)
              },
              options(socket)
            )

          {:ok, {entry.client_name, result}}
        end)

      refused =
        Enum.flat_map(results, fn
          {_name, {:ok, _receipt}} -> []
          {name, {:error, error}} -> Enum.map(Accounts.error_messages(error), &"#{name}: #{&1}")
        end)

      cond do
        results == [] ->
          {:noreply, problems(socket, :receipts, ["Choose a file to add"])}

        refused == [] ->
          words =
            if length(results) == 1, do: "The receipt is added.", else: "The receipts are added."

          reopen(socket, words)

        true ->
          # The page opens again with the files that went in, and says why
          # the others did not.
          {:noreply,
           socket
           |> put_flash(:error, Enum.join(refused, ". "))
           |> push_navigate(to: path(socket))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("take_off", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.receipts, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      receipt ->
        socket.assigns.role
        |> Expenses.take_off_receipt(receipt, options(socket))
        |> after_write(socket, "The receipt is taken off.")
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Opens the page again after a write, or shows what was wrong. A second
  # person who decided a moment before gets the page again, with the
  # decision of the first.
  defp after_write(result, socket, words) do
    case result do
      {:error, error} ->
        if Expenses.stale?(error) do
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Another person changed the expense a moment ago. This is how it is now."
           )
           |> push_navigate(to: path(socket))}
        else
          {:noreply, problems(socket, :page, Accounts.error_messages(error))}
        end

      _done ->
        reopen(socket, words)
    end
  end

  defp problems(socket, place, list), do: assign(socket, problems: list, problems_at: place)

  defp reopen(socket, words) do
    {:noreply, socket |> put_flash(:info, words) |> push_navigate(to: path(socket))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:expenses}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/expenses"}>Expenses</.link>
      </nav>

      <.header>
        {@expense.description}
        <:subtitle>Expense {@expense.number}</:subtitle>
        <:actions>
          <.link
            :if={@can.revise?}
            navigate={~p"/o/#{@organisation.short_name}/expenses/#{@expense.id}/edit"}
            data-variant="secondary"
          >
            Change
          </.link>
          <.button
            :if={@can.withdraw?}
            type="button"
            phx-click="withdraw"
            data-confirm="Withdraw the expense? It leaves the lists."
          >
            Withdraw
          </.button>
        </:actions>
      </.header>

      <.problems :if={@problems_at == :page} list={@problems} />

      <.expense_card expense={@expense} organisation={@organisation} people={@people} />

      <.decision expense={@expense} people={@people} can={@can} />

      <.payment
        expense={@expense}
        organisation={@organisation}
        people={@people}
        can={@can}
        max_date={@max_date}
      />

      <.receipts
        expense={@expense}
        receipts={@receipts}
        organisation={@organisation}
        removable={@removable}
        upload={assigns[:uploads][:receipts]}
        problems={if @problems_at == :receipts, do: @problems, else: []}
      />

      <.history events={@events} organisation={@organisation} people={@people} />
    </Layouts.app>
    """
  end
end
