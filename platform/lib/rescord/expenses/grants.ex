defmodule Rescord.Expenses.Grants do
  @moduledoc """
  What a role can do with the expenses of an organisation (ADR 0024 and
  ADR 0082).

  **Each role reads its own expenses**, and their receipts: the expenses
  that the person recorded, and those that name the person as the one whom
  the organisation pays back. What a member paid and is owed is not for each
  other member.

  The power `:expenses` records an expense, changes and withdraws the
  person's own, attaches a receipt, and removes a receipt that the person
  added. A member and an administrator have it at first.

  The power `:manage_expenses` reads each expense and each receipt, records
  an expense for another member, changes each one, decides, records the
  payment back to a member, opens a decision again, and takes off each
  receipt. Only the administrators have it at first (ADR 0040).
  """

  @behaviour Rescord.Accounts.Grants

  import Ash.Expr, only: [expr: 1, actor: 1]

  alias Rescord.Expenses.{Expense, Receipt}

  @impl true
  def reads, do: [{Expense, :read, :own}, {Receipt, :read, :of_own_expense}]

  @impl true
  def powers do
    %{
      expenses: [
        {Expense, :submit, :all},
        {Expense, :revise, :own},
        {Expense, :withdraw, :own},
        {Receipt, :attach, :all},
        {Receipt, :remove, :own}
      ],
      manage_expenses:
        [{Expense, :read, :all}, {Receipt, :read, :all}] ++
          for(
            action <- [
              :record,
              :revise,
              :set_tax,
              :approve,
              :decline,
              :reimburse,
              :reopen,
              :withdraw
            ],
            do: {Expense, action, :all}
          ) ++
          [{Receipt, :attach, :all}, {Receipt, :remove, :all}, {Receipt, :discard, :all}]
    }
  end

  @impl true
  def filter(Expense, :own), do: expr(author_id == ^actor(:id) or payer_id == ^actor(:id))
  def filter(Receipt, :own), do: expr(author_id == ^actor(:id))

  def filter(Receipt, :of_own_expense),
    do: expr(exists(expense, author_id == ^actor(:id) or payer_id == ^actor(:id)))

  def filter(_resource, _scope), do: nil
end
