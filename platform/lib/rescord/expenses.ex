defmodule Rescord.Expenses do
  @moduledoc """
  The expenses of an organisation: what its members and the organisation
  itself paid for (`docs/domain.md`, section 5.14, and ADR 0082).

  A member records an expense with `submit_expense/2`, and adds its receipts
  with `attach_receipt/2`. A person who manages the expenses decides it with
  `approve_expense/2` or `decline_expense/3`, and records with
  `reimburse_expense/3` that the organisation paid the member back.

  Rescord is not an accounting system. It has no ledger, sends no money and
  converts no amount. `report/2` gives the expenses to a CSV file and to a
  PDF, for the system that does the accounts.

  An amount is money in one currency (AshMoney). A sum here is always a
  list, with one amount for each currency: `figures/1` and `sum/1` add no
  two currencies.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query

  alias Rescord.Accounts
  alias Rescord.Expenses.{Expense, Receipt}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true
    deps [Rescord, Rescord.Accounts, Rescord.Lists, Rescord.Residents]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Expenses.Expense do
      define :expenses, action: :read
      define :expense, action: :read, get_by: [:id], not_found_error?: false
      define :submit_expense, action: :submit
      define :record_expense, action: :record
      define :revise_expense, action: :revise
      define :approve_expense, action: :approve
      define :decline_expense, action: :decline, args: [:decline_reason]
      define :reimburse_expense, action: :reimburse
      define :reopen_expense, action: :reopen
      define :withdraw_expense, action: :withdraw
    end

    resource Rescord.Expenses.Receipt do
      define :receipts, action: :read
      define :receipt, action: :read, get_by: [:id], not_found_error?: false
      define :attach_receipt, action: :attach
      define :remove_receipt, action: :remove
      define :discard_receipt, action: :discard
    end
  end

  @typedoc "A count of expenses, and their sum as one amount for each currency."
  @type sum :: %{count: non_neg_integer, amounts: [Money.t()]}

  @typedoc """
  The sums at the top of the page of the expenses, of the expenses that the
  actor reads:

    * `waiting` - the expenses that wait for a decision;
    * `to_pay_back` - the approved expenses that a member paid, and
      `members`, the number of members that they are owed to;
    * `spent` - the expenses of this month, by the date of the payment,
      that are approved or paid back;
    * `owed` - the part of `to_pay_back` that the organisation owes to the
      actor;
    * `paid_back` - what the organisation paid back to the actor in this
      month, by the date of the payment back;
    * `month` - the first day of this month in the organisation.
  """
  @type figures :: %{
          waiting: sum,
          to_pay_back: sum,
          members: non_neg_integer,
          spent: sum,
          owed: sum,
          paid_back: sum,
          month: Date.t()
        }

  @doc "What a page loads with an expense to show it in a list."
  @spec summary() :: keyword
  def summary, do: [:status, :receipt_count, category: [:label], resident: [:name]]

  @doc """
  The sums at the top of the page of the expenses. `opts` names the
  organisation in `:tenant` and the person in `:actor`: a person who does
  not manage the expenses gets the sums of their own.
  """
  @spec figures(keyword) :: {:ok, figures} | {:error, term}
  def figures(opts \\ []) do
    today = Accounts.today(Keyword.fetch!(opts, :tenant))
    first = Date.beginning_of_month(today)
    last = Date.end_of_month(today)

    actor_id =
      case opts[:actor] do
        %{id: id} -> id
        _nobody -> nil
      end

    Expense
    |> Ash.Query.filter(
      state == :submitted or (state == :approved and paid_by == :member) or
        (state in [:approved, :reimbursed] and incurred_on >= ^first and incurred_on <= ^last) or
        (state == :reimbursed and reimbursed_on >= ^first and reimbursed_on <= ^last)
    )
    |> Ash.Query.select([:state, :paid_by, :payer_id, :amount, :incurred_on, :reimbursed_on])
    |> Ash.read(opts)
    |> case do
      {:ok, expenses} ->
        owed = Enum.filter(expenses, &(&1.state == :approved and &1.paid_by == :member))
        in_month? = &(Date.compare(&1, first) != :lt and Date.compare(&1, last) != :gt)

        {:ok,
         %{
           waiting: sum(Enum.filter(expenses, &(&1.state == :submitted))),
           to_pay_back: sum(owed),
           members: owed |> Enum.map(& &1.payer_id) |> Enum.uniq() |> length(),
           spent:
             sum(
               Enum.filter(
                 expenses,
                 &(&1.state in [:approved, :reimbursed] and in_month?.(&1.incurred_on))
               )
             ),
           owed: sum(Enum.filter(owed, &(actor_id && &1.payer_id == actor_id))),
           paid_back:
             sum(
               Enum.filter(
                 expenses,
                 &(((&1.state == :reimbursed and actor_id) && &1.payer_id == actor_id) and
                     in_month?.(&1.reimbursed_on))
               )
             ),
           month: first
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  The count of a list of expenses, and their sum: one amount for each
  currency, in the order of the codes. Rescord converts no amount, so it
  adds no two currencies.

  ## Examples

      iex> Rescord.Expenses.sum([%{amount: Money.new(:AUD, "10.50")}, %{amount: Money.new(:AUD, 2)}])
      %{count: 2, amounts: [Money.new(:AUD, "12.50")]}

      iex> Rescord.Expenses.sum([])
      %{count: 0, amounts: []}
  """
  @spec sum([%{amount: Money.t()}]) :: sum
  def sum(expenses) do
    amounts =
      expenses
      |> Enum.group_by(& &1.amount.currency, & &1.amount)
      |> Enum.sort_by(fn {currency, _amounts} -> to_string(currency) end)
      |> Enum.map(fn {_currency, [first | rest]} -> Enum.reduce(rest, first, &Money.add!/2) end)

    %{count: length(expenses), amounts: amounts}
  end

  @typedoc """
  What limits the expenses of `report/2`. Each key is optional:

    * `status` - `:submitted`, `:approved`, `:to_pay_back`, `:reimbursed`
      or `:declined`, as the calculation `status` of an expense;
    * `category_id`, `resident_id` - the category, and the resident;
    * `paid_by` - `:member` or `:organisation`;
    * `from`, `to` - the first and the last date of the payment;
    * `search` - words in what the expense was for, or in who was paid.
  """
  @type limits :: %{
          optional(:status) => atom,
          optional(:category_id) => String.t(),
          optional(:resident_id) => String.t(),
          optional(:paid_by) => :member | :organisation,
          optional(:from) => Date.t(),
          optional(:to) => Date.t(),
          optional(:search) => String.t()
        }

  @doc """
  The expenses that the actor reads, the newest payment first, each with
  what `summary/0` names. A CSV file and a PDF are made from this. `limits`
  holds what the list on the page holds.
  """
  @spec report(limits, keyword) :: {:ok, [Ash.Resource.record()]} | {:error, term}
  def report(limits \\ %{}, opts \\ []) do
    Expense
    |> limit_to(limits)
    |> Ash.Query.sort(incurred_on: :desc, number: :desc)
    |> Ash.Query.load(summary())
    |> Ash.read(opts)
  end

  @doc """
  The query of the list on the page of the expenses: the expenses within
  `limits`, the newest payment first, each with what `summary/0` names. The
  page gives it to the collection, which adds its filters and its sort.
  """
  @spec list_query(limits, keyword) :: Ash.Query.t()
  def list_query(limits \\ %{}, opts \\ []) do
    query =
      Expense
      |> limit_to(limits)
      |> Ash.Query.sort(incurred_on: :desc, number: :desc)
      |> Ash.Query.load(summary())

    query_to_expenses(%{}, [query: query] ++ opts)
  end

  @doc "A query of the expenses with the limits of `report/2`, for a page that adds its own."
  @spec limit_to(Ash.Query.t() | module, limits) :: Ash.Query.t()
  def limit_to(query, limits) do
    Enum.reduce(limits, Ash.Query.new(query), fn
      {_key, nil}, query ->
        query

      {:status, status}, query when is_atom(status) ->
        Ash.Query.filter(query, status == ^status)

      {:category_id, id}, query when is_binary(id) ->
        Ash.Query.filter(query, category_id == ^id)

      {:resident_id, id}, query when is_binary(id) ->
        Ash.Query.filter(query, resident_id == ^id)

      {:paid_by, paid_by}, query when paid_by in [:member, :organisation] ->
        Ash.Query.filter(query, paid_by == ^paid_by)

      {:from, %Date{} = date}, query ->
        Ash.Query.filter(query, incurred_on >= ^date)

      {:to, %Date{} = date}, query ->
        Ash.Query.filter(query, incurred_on <= ^date)

      {:search, words}, query when is_binary(words) and words != "" ->
        words = String.downcase(words)

        Ash.Query.filter(
          query,
          contains(fragment("lower(?)", description), ^words) or
            contains(fragment("lower(?)", payee), ^words)
        )

      _other, query ->
        query
    end)
  end

  @typedoc """
  One thing that happened to an expense:

    * `at` - the instant;
    * `user_id` - the user who did it, or `nil`;
    * `action` - the action of the expense (`:submit`, `:record`, `:revise`,
      `:approve`, `:decline`, `:reimburse`, `:reopen`), or `:attach` and
      `:take_off` for a receipt;
    * `changes` - what the action changed, by the name of the attribute as
      text. For a receipt it holds `"name"`.
  """
  @type event :: %{
          at: DateTime.t(),
          user_id: String.t() | nil,
          action: atom,
          changes: map
        }

  @doc """
  What happened to an expense, the newest first, from the paper trail of
  the expense and of its receipts.

  The policy of a version refuses each actor (ADR 0063). This function
  reads the expense with the options of the caller first, and reads the
  versions only when the caller can read the expense.
  """
  @spec history(String.t(), keyword) :: {:ok, [event]} | {:error, :not_found | term}
  def history(id, opts \\ []) do
    with {:ok, %Expense{}} <- expense(id, opts) do
      inner = [tenant: Keyword.fetch!(opts, :tenant), authorize?: false]

      of_expense =
        Expense.Version
        |> Ash.Query.filter(version_source_id == ^id)
        |> Ash.read!(inner)
        |> Enum.map(&event(&1, &1.version_action_name, &1.changes))

      attached =
        Receipt.Version
        |> Ash.Query.filter(
          version_action_type == :create and fragment("(?->>'expense_id') = ?", changes, ^id)
        )
        |> Ash.read!(inner)

      names = Map.new(attached, &{&1.version_source_id, %{"name" => &1.changes["name"]}})
      receipt_ids = Map.keys(names)

      taken_off =
        Receipt.Version
        |> Ash.Query.filter(
          version_source_id in ^receipt_ids and version_action_name in [:remove, :discard]
        )
        |> Ash.read!(inner)

      of_receipts =
        Enum.map(attached, &event(&1, :attach, names[&1.version_source_id])) ++
          Enum.map(taken_off, &event(&1, :take_off, names[&1.version_source_id]))

      {:ok, Enum.sort_by(of_expense ++ of_receipts, & &1.at, {:desc, DateTime})}
    else
      {:ok, nil} -> {:error, :not_found}
      {:error, error} -> {:error, error}
    end
  end

  defp event(version, action, changes) do
    %{
      at: version.version_inserted_at,
      user_id: version.user_id,
      action: action,
      changes: changes || %{}
    }
  end

  @doc "The receipts of one expense that the actor reads, the oldest first."
  @spec receipts_of(String.t(), keyword) :: {:ok, [Ash.Resource.record()]} | {:error, term}
  def receipts_of(expense_id, opts \\ []) do
    Receipt
    |> Ash.Query.filter(expense_id == ^expense_id)
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.read(opts)
  end

  @doc """
  A receipt and the bytes of its file. The result is `{:error, :not_found}`
  unless the actor can read the receipt and the store has the file. A page
  that sends the file uses this.
  """
  @spec receipt_file(String.t(), keyword) :: {:ok, map, binary} | {:error, :not_found | term}
  def receipt_file(id, opts \\ []), do: file_of(id, :key, opts)

  @doc "A receipt and the bytes of the thumbnail of its photo. A PDF has none."
  @spec receipt_thumbnail(String.t(), keyword) ::
          {:ok, map, binary} | {:error, :not_found | term}
  def receipt_thumbnail(id, opts \\ []), do: file_of(id, :thumbnail_key, opts)

  defp file_of(id, field, opts) do
    with {:ok, %{} = receipt} <- receipt(id, opts),
         key when is_binary(key) <- Map.fetch!(receipt, field),
         {:ok, bytes} <- Rescord.Storage.get(key) do
      {:ok, receipt, bytes}
    else
      {:error, error} -> {:error, error}
      _nothing -> {:error, :not_found}
    end
  end

  @doc """
  Whether the error of an action says that the expense changed after the
  caller read it: another person decided it a moment before.
  """
  @spec stale?(term) :: boolean
  def stale?(%{errors: errors}) when is_list(errors),
    do: Enum.any?(errors, &match?(%Ash.Error.Changes.StaleRecord{}, &1))

  def stale?(_error), do: false

  @doc "The largest file of a receipt, in bytes."
  defdelegate max_receipt_size(), to: Rescord.Storage.Upload, as: :max_size

  @doc "The most receipts that a person adds to an expense at one time."
  @spec max_receipts() :: pos_integer
  def max_receipts, do: 5

  @doc """
  Whether a role can run an action of an expense (`:expense`) or of a
  receipt (`:receipt`) at all. A page asks this to decide what to show.
  """
  @spec role_can?(term, :expense | :receipt, atom) :: boolean
  def role_can?(role, :expense, action), do: Accounts.granted?(role, Expense, action)
  def role_can?(role, :receipt, action), do: Accounts.granted?(role, Receipt, action)

  @doc """
  Whether a user with a role can run an action on one expense: the role has
  the grant for this expense, and the state of the expense lets the action
  run. A page asks this to show a button only where the action would work.
  The policy and the action decide when it runs.
  """
  @spec can?(term, map, Ash.Resource.record(), atom) :: boolean
  def can?(role, user, %Expense{} = expense, action) do
    state_lets?(expense, action) and in_scope?(role, user, expense, action)
  end

  defp state_lets?(%{state: state}, action) when action in [:revise, :withdraw],
    do: state in [:submitted, :declined]

  defp state_lets?(%{state: state}, action) when action in [:approve, :decline],
    do: state == :submitted

  defp state_lets?(expense, :reimburse),
    do: expense.state == :approved and expense.paid_by == :member

  defp state_lets?(%{state: state}, :reopen), do: state in [:approved, :declined, :reimbursed]
  defp state_lets?(_expense, _action), do: false

  defp in_scope?(:root, _user, _expense, _action), do: true

  defp in_scope?(role, %{id: user_id}, expense, action) do
    case Accounts.Grants.scope(role, Expense, action) do
      {:ok, :all} -> true
      {:ok, :own} -> user_id in [expense.author_id, expense.payer_id]
      _none -> false
    end
  end

  @doc """
  Whether a user with a role can take a receipt off its expense: each
  receipt for a person who manages the expenses, and a receipt that the
  person added while the expense waits or after it was declined.
  """
  @spec can_take_off?(term, map, Ash.Resource.record(), Ash.Resource.record()) :: boolean
  def can_take_off?(:root, _user, _expense, _receipt), do: true

  def can_take_off?(role, %{id: user_id}, %Expense{} = expense, %Receipt{} = receipt) do
    Accounts.granted?(role, Receipt, :discard) or
      (Accounts.granted?(role, Receipt, :remove) and receipt.author_id == user_id and
         expense.state in [:submitted, :declined])
  end

  @doc """
  Takes a receipt off its expense, with `discard` for a role that has it and
  with `remove` for each other role.
  """
  @spec take_off_receipt(term, Ash.Resource.record(), keyword) :: :ok | {:error, term}
  def take_off_receipt(role, %Receipt{} = receipt, opts) do
    if role == :root or Accounts.granted?(role, Receipt, :discard),
      do: discard_receipt(receipt, opts),
      else: remove_receipt(receipt, opts)
  end
end
