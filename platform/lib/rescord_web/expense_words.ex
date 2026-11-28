defmodule RescordWeb.ExpenseWords do
  @moduledoc """
  The words of the expenses (ADR 0082): the state of an expense for a
  person, an amount of money as text, what happened to an expense, and the
  row of an expense in a CSV file.

  A page writes an amount with `money/1`, in the locale of the request. A
  form and a CSV file take `plain/1`: the number with the decimal places of
  its currency, and no sign of a currency.
  """

  alias Rescord.Accounts
  alias RescordWeb.{JournalWords, ResidentWords}

  # The states in the order of the work: what waits is first.
  @status [
    submitted: {"Waits for a decision", "info"},
    to_pay_back: {"To pay back", "info"},
    approved: {"Approved", "ok"},
    reimbursed: {"Paid back", "ok"},
    declined: {"Declined", "none"}
  ]

  @doc "The state of an expense in words, from its calculation `status`."
  @spec status(atom) :: String.t()
  def status(status), do: @status |> Keyword.fetch!(status) |> elem(0)

  @doc "The kind of the state, for `<.state>`: what waits for a person is `info`."
  @spec status_kind(atom) :: String.t()
  def status_kind(status), do: @status |> Keyword.fetch!(status) |> elem(1)

  @doc "The states that a filter offers, as `{words, value}`."
  @spec status_options() :: [{String.t(), String.t()}]
  def status_options,
    do: for({status, {words, _kind}} <- @status, do: {words, Atom.to_string(status)})

  @doc "The state with the text of a field, or `:error`. It makes no atom."
  @spec status_of(term) :: {:ok, atom} | :error
  def status_of(text) when is_binary(text) do
    case Enum.find(Keyword.keys(@status), &(Atom.to_string(&1) == text)) do
      nil -> :error
      status -> {:ok, status}
    end
  end

  def status_of(_other), do: :error

  @doc "Who paid, from the text of a field, or `:error`."
  @spec paid_by_of(term) :: {:ok, :member | :organisation} | :error
  def paid_by_of("member"), do: {:ok, :member}
  def paid_by_of("organisation"), do: {:ok, :organisation}
  def paid_by_of(_other), do: :error

  @doc """
  An amount for a person, in the locale of the request: `$186.00` for
  Australian dollars in English (Australia).
  """
  @spec money(Money.t()) :: String.t()
  def money(%Money{} = money), do: RescordWeb.Locale.money(money)

  @doc """
  A sum for a person: one amount for each currency. A sum of nothing is
  zero in `currency`, the currency of the organisation.
  """
  @spec amounts(%{amounts: [Money.t()]}, String.t()) :: String.t()
  def amounts(%{amounts: []}, currency), do: money(Money.new(currency, 0))
  def amounts(%{amounts: amounts}, _currency), do: Enum.map_join(amounts, " and ", &money/1)

  @doc """
  The name of the tax of an organisation for a label, such as `GST`, or
  `Tax` for an organisation that names none now: an expense keeps its tax
  when the name goes.

      iex> RescordWeb.ExpenseWords.tax_name(%{tax_name: "GST"})
      "GST"

      iex> RescordWeb.ExpenseWords.tax_name(%{tax_name: nil})
      "Tax"
  """
  @spec tax_name(map) :: String.t()
  def tax_name(%{tax_name: name}) when is_binary(name), do: name
  def tax_name(_organisation), do: "Tax"

  @doc """
  The number of an amount as plain text, with the decimal places of its
  currency: what a form shows, and what a CSV file holds.

      iex> RescordWeb.ExpenseWords.plain(Money.new(:AUD, "186"))
      "186.00"

      iex> RescordWeb.ExpenseWords.plain(Money.new(:JPY, 1200))
      "1200"
  """
  @spec plain(Money.t()) :: String.t()
  def plain(%Money{amount: amount, currency: currency}) do
    amount |> Decimal.round(Accounts.currency_digits(currency)) |> Decimal.to_string(:normal)
  end

  @doc "The name of a currency, for example `Australian Dollar`, or its code."
  @spec currency_name(String.t() | atom) :: String.t()
  def currency_name(code), do: RescordWeb.Locale.currency_name(code)

  @doc "The name of a currency for more than one, for example `Australian dollars`, or its code."
  @spec currency_plural(String.t() | atom) :: String.t()
  def currency_plural(code), do: RescordWeb.Locale.currency_plural(code)

  @doc "A person of the organisation by the id of the user: the email address."
  @spec person(%{String.t() => String.t()}, String.t() | nil) :: String.t()
  def person(_people, nil), do: "Rescord"
  def person(people, id), do: Map.get(people, id, "A person who left")

  @doc "Who paid an expense: the member, or the organisation."
  @spec paid_by(map, map, map) :: String.t()
  def paid_by(%{paid_by: :organisation}, organisation, _people), do: organisation.name
  def paid_by(%{payer_id: payer_id}, _organisation, people), do: person(people, payer_id)

  @doc """
  A count with its noun: `1 expense`, `2 expenses`.

      iex> RescordWeb.ExpenseWords.count(1, "expense")
      "1 expense"

      iex> RescordWeb.ExpenseWords.count(0, "receipt")
      "0 receipts"
  """
  @spec count(non_neg_integer, String.t()) :: String.t()
  def count(1, noun), do: "1 #{noun}"
  def count(number, noun), do: "#{number} #{noun}s"

  @doc """
  The size of a file in words.

      iex> RescordWeb.ExpenseWords.size(412_000)
      "412 kB"

      iex> RescordWeb.ExpenseWords.size(2_500_000)
      "2.5 MB"

      iex> RescordWeb.ExpenseWords.size(900)
      "1 kB"
  """
  @spec size(non_neg_integer) :: String.t()
  def size(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)} MB"
  def size(bytes), do: "#{max(1, round(bytes / 1000))} kB"

  @doc "The month of a date in words: `November 2026`."
  @spec month(Date.t()) :: String.t()
  def month(%Date{} = date), do: Calendar.strftime(date, "%B %Y")

  @doc "An instant in the time zone of the organisation, in words."
  @spec instant(map, DateTime.t()) :: String.t()
  def instant(organisation, %DateTime{} = instant),
    do: JournalWords.time(Accounts.local_time(organisation, instant))

  # The facts of an expense that a person changes, and their names in a
  # sentence. The paper trail names an attribute as text.
  @facts [
    {"amount", "the amount"},
    {"tax", "the tax"},
    {"incurred_on", "the date"},
    {"payee", "who was paid"},
    {"description", "what it was for"},
    {"category_id", "the category"},
    {"resident_id", "the resident"},
    {"note", "the note"}
  ]

  @doc """
  What a person did to an expense, as the end of a sentence that starts
  with the person: `approved the expense.` An event is one of
  `Rescord.Expenses.history/2`.
  """
  @spec event(map) :: String.t()
  def event(%{action: action}) when action in [:submit, :record], do: "recorded the expense."
  def event(%{action: :approve}), do: "approved the expense."
  def event(%{action: :reopen}), do: "opened the decision again."

  def event(%{action: :decline, changes: changes}) do
    case changes["decline_reason"] do
      reason when is_binary(reason) -> "declined the expense: #{reason}"
      _none -> "declined the expense."
    end
  end

  def event(%{action: :reimburse, changes: changes}) do
    on =
      case Date.from_iso8601(to_string(changes["reimbursed_on"])) do
        {:ok, date} -> " of #{ResidentWords.date(date)}"
        _none -> ""
      end

    reference =
      case changes["reimbursement_reference"] do
        text when is_binary(text) and text != "" -> ", with the reference #{text}"
        _none -> ""
      end

    "recorded the payment#{on}#{reference}."
  end

  def event(%{action: :revise, changes: changes}) do
    case for {key, words} <- @facts, Map.has_key?(changes, key), do: words do
      [] -> "sent the expense again."
      words -> "changed #{Enum.join(words, ", ")}."
    end
  end

  def event(%{action: :set_tax}), do: "corrected the tax in the amount."

  def event(%{action: :attach, changes: changes}), do: "added the receipt #{changes["name"]}."

  def event(%{action: :take_off, changes: changes}),
    do: "took off the receipt #{changes["name"]}."

  def event(_other), do: "changed the expense."

  @doc "The header of the CSV file of the list of the expenses."
  @spec csv_header() :: [String.t()]
  def csv_header do
    [
      "number",
      "date",
      "description",
      "paid to",
      "category",
      "resident",
      "paid by",
      "member",
      "amount",
      "tax",
      "currency",
      "state",
      "recorded by",
      "decided by",
      "decided on",
      "decline reason",
      "paid back on",
      "reference",
      "receipts"
    ]
  end

  @doc """
  The row of an expense in the CSV file, in the order of `csv_header/0`.
  The amount is a number, so that a spreadsheet can add the column, and the
  code of the currency is beside it. The tax is the part of the amount that
  is tax, as a number, or empty for an expense with none.
  """
  @spec csv_row(map, map, map) :: [term]
  def csv_row(expense, organisation, people) do
    [
      expense.number,
      expense.incurred_on,
      expense.description,
      expense.payee,
      expense.category && to_string(expense.category.label),
      expense.resident && (expense.resident.name || "A resident with no name"),
      if(expense.paid_by == :member, do: "member", else: "organisation"),
      expense.payer_id && person(people, expense.payer_id),
      Decimal.round(expense.amount.amount, Accounts.currency_digits(expense.amount.currency)),
      expense.tax &&
        Decimal.round(expense.tax.amount, Accounts.currency_digits(expense.tax.currency)),
      Atom.to_string(expense.amount.currency),
      status(expense.status),
      person(people, expense.author_id),
      expense.decided_by_id && person(people, expense.decided_by_id),
      expense.decided_at && Accounts.local_date(organisation, expense.decided_at),
      expense.decline_reason,
      expense.reimbursed_on,
      expense.reimbursement_reference,
      expense.receipt_count
    ]
  end
end
