defmodule RescordWeb.ExpenseFormLive do
  @moduledoc """
  The form of an expense (ADR 0082): a new one at
  `/o/<short name>/expenses/new`, and a change at
  `/o/<short name>/expenses/<id>/edit`.

  A new expense says who paid: the person, or the organisation. A person
  who manages the expenses can also name another member. The form takes up
  to five receipts with the expense. `?resident=<id>` chooses a resident
  for a new expense.

  The page records the expense first, and then adds each receipt to it. A
  receipt that Rescord refuses does not undo the expense: the page of the
  expense says which file did not go in.

  The page reads only the fields that it knows from what the browser sends,
  and makes no atom from it.
  """

  use RescordWeb, :live_view

  import RescordWeb.ExpenseComponents

  alias Rescord.{Accounts, Expenses, Lists, Residents}
  alias RescordWeb.ExpenseWords

  @impl true
  def mount(params, _session, socket) do
    role = socket.assigns.role
    user = socket.assigns.current_user

    case socket.assigns.live_action do
      :new ->
        if Expenses.role_can?(role, :expense, :submit) do
          {:ok,
           socket
           |> assign(page_title: "Record an expense", expense: nil)
           |> assign_choices()
           |> assign_form(%{
             "paid_by" => "member",
             "incurred_on" => Date.to_iso8601(Accounts.today(socket.assigns.organisation)),
             "resident_id" => non_blank(params["resident"]) || ""
           })
           |> allow_receipts()}
        else
          {:ok, back(socket, "Your role cannot record an expense.")}
        end

      :edit ->
        with id when is_binary(id) <- params["id"],
             {:ok, _uuid} <- Ecto.UUID.cast(id),
             {:ok, %{} = expense} <-
               Expenses.expense(id, [load: Expenses.summary()] ++ options(socket)),
             true <- Expenses.can?(role, user, expense, :revise) do
          {:ok,
           socket
           |> assign(page_title: "Change #{expense.description}", expense: expense)
           |> assign_choices()
           |> assign_form(fields_of(expense))
           |> allow_receipts()}
        else
          _no_expense -> {:ok, back(socket, "There is no such expense to change.")}
        end
    end
  end

  defp back(socket, words) do
    socket
    |> put_flash(:error, words)
    |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/expenses")
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  # What the form offers: the categories that are not retired, and the one
  # of the expense; the residents; and, for a person who records an expense
  # of another member, the other members.
  defp assign_choices(socket) do
    options = options(socket)
    expense = socket.assigns.expense
    {:ok, categories} = Lists.values(:expense_category, options)
    {:ok, residents} = Residents.residents([load: [:name]] ++ options)

    payers =
      if is_nil(expense) and Expenses.role_can?(socket.assigns.role, :expense, :record) do
        {:ok, members} = Accounts.members([load: [:email]] ++ options)

        for member <- members, member.user_id != socket.assigns.current_user.id do
          {to_string(member.email), member.user_id}
        end
        |> Enum.sort()
      else
        []
      end

    assign(socket,
      categories:
        for value <- categories,
            not value.retired or (expense && expense.category_id == value.id) do
          {to_string(value.label), value.id}
        end,
      residents:
        residents
        |> Enum.map(&{&1.name || "A resident with no name", &1.id})
        |> Enum.sort_by(fn {name, _id} -> String.downcase(name) end),
      payers: payers,
      max_date: Date.to_iso8601(Accounts.today(socket.assigns.organisation)),
      problems: []
    )
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

  defp assign_form(socket, fields), do: assign(socket, form: typed_form(fields, as: :expense))

  defp fields_of(expense) do
    %{
      "amount" => ExpenseWords.plain(expense.amount),
      "tax" => if(expense.tax, do: ExpenseWords.plain(expense.tax), else: ""),
      "incurred_on" => Date.to_iso8601(expense.incurred_on),
      "payee" => expense.payee,
      "description" => expense.description,
      "category_id" => expense.category_id,
      "resident_id" => expense.resident_id || "",
      "note" => expense.note || ""
    }
  end

  @impl true
  def handle_event("choose", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_receipt", %{"ref" => ref}, socket) when is_binary(ref) do
    {:noreply, cancel_upload(socket, :receipts, ref)}
  end

  def handle_event("save", %{"expense" => fields}, socket) when is_map(fields) do
    case save(socket, fields) do
      {:ok, expense} ->
        problems = attach(socket, expense)
        path = ~p"/o/#{socket.assigns.organisation.short_name}/expenses/#{expense.id}"

        socket =
          case problems do
            [] -> put_flash(socket, :info, saved_words(socket, expense))
            problems -> put_flash(socket, :error, receipt_words(problems))
          end

        {:noreply, push_navigate(socket, to: path)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign(problems: Accounts.error_messages(error))
         |> assign_form(fields)}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # A new expense of the person, or of the organisation, is `submit`. An
  # expense of another member, and one of the organisation from a person
  # who manages the expenses, is `record`.
  defp save(%{assigns: %{expense: nil}} = socket, fields) do
    facts = facts(fields, socket.assigns.organisation)
    can_record? = Expenses.role_can?(socket.assigns.role, :expense, :record)

    case fields["paid_by"] do
      "other" when can_record? ->
        facts
        |> Map.merge(%{paid_by: :member, payer_id: non_blank(fields["payer_id"])})
        |> Expenses.record_expense(options(socket))

      "organisation" when can_record? ->
        facts |> Map.put(:paid_by, :organisation) |> Expenses.record_expense(options(socket))

      "organisation" ->
        facts |> Map.put(:paid_by, :organisation) |> Expenses.submit_expense(options(socket))

      _the_person ->
        facts |> Map.put(:paid_by, :member) |> Expenses.submit_expense(options(socket))
    end
  end

  defp save(%{assigns: %{expense: expense}} = socket, fields),
    do:
      Expenses.revise_expense(
        expense,
        facts(fields, socket.assigns.organisation),
        options(socket)
      )

  # The form has the field of the tax only while the organisation names a
  # tax. With no field, an expense keeps the tax that it has.
  defp facts(fields, %{tax_name: name}) when is_binary(name),
    do: Map.put(facts(fields), :tax, amount(fields["tax"]))

  defp facts(fields, _organisation), do: facts(fields)

  defp facts(fields) do
    %{
      amount: amount(fields["amount"]),
      incurred_on: non_blank(fields["incurred_on"]),
      payee: non_blank(fields["payee"]),
      description: non_blank(fields["description"]),
      category_id: non_blank(fields["category_id"]),
      resident_id: non_blank(fields["resident_id"]),
      note: non_blank(fields["note"])
    }
  end

  # The amount as the person typed it, with no space. `1,234.50` is not a
  # number here: the action refuses it, and the person types `1234.50`.
  defp amount(text) do
    case non_blank(text) do
      nil -> nil
      text -> String.replace(text, " ", "")
    end
  end

  # Adds each file of the form to the expense, and returns what Rescord
  # refused, each with the name of its file.
  defp attach(socket, expense) do
    if socket.assigns[:uploads][:receipts] do
      socket
      |> consume_uploaded_entries(:receipts, fn %{path: path}, entry ->
        result =
          Expenses.attach_receipt(
            %{expense_id: expense.id, name: entry.client_name, content: File.read!(path)},
            options(socket)
          )

        {:ok, {entry.client_name, result}}
      end)
      |> Enum.flat_map(fn
        {_name, {:ok, _receipt}} -> []
        {name, {:error, error}} -> Enum.map(Accounts.error_messages(error), &"#{name}: #{&1}")
      end)
    else
      []
    end
  end

  defp saved_words(%{assigns: %{expense: nil}}, %{state: :approved}),
    do: "The expense is recorded and approved."

  defp saved_words(%{assigns: %{expense: nil}}, _expense),
    do: "The expense is recorded. It waits for a decision."

  defp saved_words(_socket, _expense), do: "The expense is changed. It waits for a decision."

  defp receipt_words(problems),
    do: "The expense is saved, but a receipt did not go in. #{Enum.join(problems, ". ")}"

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
        <span :if={@expense}>
          ›
          <.link navigate={~p"/o/#{@organisation.short_name}/expenses/#{@expense.id}"}>
            {@expense.description}
          </.link>
        </span>
      </nav>

      <.header>
        {if @expense, do: "Change the expense", else: "Record an expense"}
        <:subtitle :if={is_nil(@expense)}>
          Something that you or {@organisation.name} paid for
        </:subtitle>
        <:subtitle :if={@expense}>Expense {@expense.number}</:subtitle>
      </.header>

      <.problems list={@problems} />

      <p :if={@expense && @expense.state == :declined} role="status">
        The expense was declined: {@expense.decline_reason} It waits for a decision again after
        you save it.
      </p>

      <p :if={@categories == []} role="status">
        The list of the expense categories is empty, and an expense needs a category. An
        administrator adds values on <.link navigate={~p"/o/#{@organisation.short_name}/lists"}>the lists page</.link>.
      </p>

      <.form for={@form} id="expense" phx-submit="save" phx-change="choose">
        <.expense_fields
          form={@form}
          new?={is_nil(@expense)}
          organisation={@organisation}
          currency={
            if @expense, do: to_string(@expense.amount.currency), else: @organisation.currency
          }
          tax_name={@organisation.tax_name}
          payers={@payers}
          categories={@categories}
          residents={@residents}
          max_date={@max_date}
        />
        <.receipt_files :if={assigns[:uploads][:receipts]} upload={@uploads.receipts} />
        <footer>
          <.button type="submit" variant="primary">
            {if @expense, do: "Save and send for a decision", else: "Send for a decision"}
          </.button>
          <.link
            navigate={
              if @expense,
                do: ~p"/o/#{@organisation.short_name}/expenses/#{@expense.id}",
                else: ~p"/o/#{@organisation.short_name}/expenses"
            }
            data-variant="secondary"
          >
            Cancel
          </.link>
        </footer>
      </.form>
    </Layouts.app>
    """
  end
end
