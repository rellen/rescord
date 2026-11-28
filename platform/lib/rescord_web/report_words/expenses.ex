defmodule RescordWeb.ReportWords.Expenses do
  @moduledoc """
  The words of the expenses of a period (`Rescord.Reports.Facts.Expenses`,
  ADR 0082). A sum is one amount for each currency, as on the page of the
  expenses: Rescord adds no two currencies.

  The report holds the tax of the expenses (ADR 0089) when the organisation
  names a tax, or when an expense of the report has one: `tax` is then the
  name of the tax, and each sum and each expense has its tax as text. With
  neither, `tax` is `nil`, and the template has no column for it.
  """

  import RescordWeb.ReportWords

  alias RescordWeb.{ExpenseWords, ResidentWords}

  # The states of an expense that the organisation accepted.
  @accepted [:approved, :to_pay_back, :reimbursed]

  def data(facts) do
    currency = facts.organisation.currency
    accepted = Enum.filter(facts.expenses, &(&1.status in @accepted))
    tax? = is_binary(facts.organisation.tax_name) or Enum.any?(facts.expenses, & &1.tax)

    %{
      frame:
        frame(
          facts,
          "Expenses",
          "From #{ResidentWords.date(facts.from)} to #{ResidentWords.date(facts.to)}"
        ),
      scope: scope(facts),
      tax: if(tax?, do: ExpenseWords.tax_name(facts.organisation)),
      summary:
        [
          %{label: "Expenses in these days", value: amount(length(facts.expenses))},
          %{label: "Approved or paid back", value: sum(accepted, currency)}
        ] ++
          if(tax?,
            do: [
              %{
                label: "#{ExpenseWords.tax_name(facts.organisation)} in approved or paid back",
                value: tax_sum(accepted, currency)
              }
            ],
            else: []
          ) ++
          [
            %{
              label: "Wait for a decision",
              value: sum(Enum.filter(facts.expenses, &(&1.status == :submitted)), currency)
            },
            %{label: "To pay back now", value: sum(facts.owed, currency)}
          ],
      by_state:
        for {words, value} <- ExpenseWords.status_options(),
            of_state = Enum.filter(facts.expenses, &(Atom.to_string(&1.status) == value)),
            of_state != [] do
          tally(words, of_state, currency)
        end,
      by_category:
        accepted
        |> Enum.group_by(&(label(&1.category) || "No category"))
        |> Enum.sort_by(fn {category, _expenses} -> category end)
        |> Enum.map(fn {category, expenses} -> tally(category, expenses, currency) end),
      owed:
        facts.owed
        |> Enum.group_by(&ExpenseWords.person(facts.people, &1.payer_id))
        |> Enum.sort_by(fn {member, _expenses} -> member end)
        |> Enum.map(fn {member, expenses} -> tally(member, expenses, currency) end),
      expenses: Enum.map(facts.expenses, &expense(&1, facts))
    }
  end

  defp expense(expense, facts) do
    %{
      number: Integer.to_string(expense.number),
      date: ResidentWords.date(expense.incurred_on),
      description: text(expense.description),
      payee: text(expense.payee),
      category: label(expense.category),
      resident: expense.resident && name(expense.resident),
      paid_by: ExpenseWords.paid_by(expense, facts.organisation, facts.people),
      state: ExpenseWords.status(expense.status),
      receipts: amount(expense.receipt_count),
      amount: ExpenseWords.money(expense.amount),
      tax: expense.tax && ExpenseWords.money(expense.tax)
    }
  end

  # A row of a sum: its label, how many expenses, their amount, and the tax
  # in it.
  defp tally(label, expenses, currency) do
    %{
      label: label,
      count: amount(length(expenses)),
      amount: sum(expenses, currency),
      tax: tax_sum(expenses, currency)
    }
  end

  defp sum(expenses, currency),
    do: expenses |> Rescord.Expenses.sum() |> ExpenseWords.amounts(currency)

  defp tax_sum(expenses, currency),
    do: expenses |> Rescord.Expenses.tax_sum() |> ExpenseWords.amounts(currency)

  defp scope(%{all?: true}),
    do: "Each expense of the organisation with a payment in these days."

  defp scope(facts) do
    "Only the expenses that #{reader(facts)} recorded or paid. " <>
      "A person who manages the expenses gets each expense of the organisation."
  end

  defp reader(%{reader: %{id: id}, people: people}), do: ExpenseWords.person(people, id)
  defp reader(_facts), do: "the person who made this report"
end
