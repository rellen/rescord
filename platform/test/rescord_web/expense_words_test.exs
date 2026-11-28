defmodule RescordWeb.ExpenseWordsTest do
  @moduledoc """
  Holds the words of the expenses to the types (ADR 0082): each state
  that an expense can show has words and a kind, and the row of the CSV
  file has a cell for each column of its header.
  """

  use ExUnit.Case, async: true

  alias Rescord.Expenses.Expense
  alias RescordWeb.ExpenseWords

  test "each state of an expense has words, a kind, and a place in the filter" do
    statuses = Ash.Resource.Info.calculation(Expense, :status).constraints[:one_of]

    for status <- statuses do
      assert is_binary(ExpenseWords.status(status))
      assert ExpenseWords.status_kind(status) in ~w(ok alert info none)
      assert ExpenseWords.status_of(Atom.to_string(status)) == {:ok, status}
    end

    assert Enum.sort(Enum.map(ExpenseWords.status_options(), &elem(&1, 1))) ==
             Enum.sort(Enum.map(statuses, &Atom.to_string/1))

    assert ExpenseWords.status_of("paid") == :error
    assert ExpenseWords.status_of(nil) == :error
  end

  test "each action of an expense that a person runs has words for what happened" do
    for action <- [:submit, :record, :revise, :approve, :decline, :reimburse, :reopen, :set_tax] do
      words = ExpenseWords.event(%{action: action, changes: %{}})
      assert String.ends_with?(words, "."), "#{action}: #{words}"
      refute words == "changed the expense."
    end

    assert ExpenseWords.event(%{action: :attach, changes: %{"name" => "a.pdf"}}) ==
             "added the receipt a.pdf."

    assert ExpenseWords.event(%{action: :revise, changes: %{"amount" => %{}, "note" => "x"}}) ==
             "changed the amount, the note."
  end

  test "an amount has the form of the locale, and a sum of nothing is zero" do
    assert ExpenseWords.money(Money.new(:AUD, "1234.5")) == "$1,234.50"
    assert ExpenseWords.amounts(%{amounts: []}, "AUD") == "$0.00"

    # Another currency has its code in English (Australia).
    assert ExpenseWords.amounts(%{amounts: [Money.new(:AUD, 5), Money.new(:NZD, 7)]}, "AUD") =~
             ~r/^\$5\.00 and NZD.7\.00$/u
  end

  test "the row of the CSV file has a cell for each column" do
    expense = %{
      number: 4,
      incurred_on: ~D[2026-11-27],
      description: "Vet consult",
      payee: "Northside Vet Clinic",
      category: %{label: "Veterinary"},
      resident: nil,
      paid_by: :member,
      payer_id: "sam",
      amount: Money.new(:AUD, "186"),
      tax: Money.new(:AUD, "16.9"),
      status: :to_pay_back,
      author_id: "sam",
      decided_by_id: "robin",
      decided_at: ~U[2026-11-27 23:30:00Z],
      decline_reason: nil,
      reimbursed_on: nil,
      reimbursement_reference: nil,
      receipt_count: 2
    }

    organisation = %Rescord.Accounts.Organisation{
      time_zone: "Australia/Brisbane",
      name: "Wattle Creek"
    }

    people = %{"sam" => "sam@example.org", "robin" => "robin@example.org"}
    row = ExpenseWords.csv_row(expense, organisation, people)

    assert length(row) == length(ExpenseWords.csv_header())

    # An expense with no tax has an empty cell, not a zero.
    assert Enum.at(ExpenseWords.csv_row(%{expense | tax: nil}, organisation, people), 9) == nil
    assert Enum.at(ExpenseWords.csv_header(), 9) == "tax"

    assert row == [
             4,
             ~D[2026-11-27],
             "Vet consult",
             "Northside Vet Clinic",
             "Veterinary",
             nil,
             "member",
             "sam@example.org",
             Decimal.new("186.00"),
             Decimal.new("16.90"),
             "AUD",
             "To pay back",
             "sam@example.org",
             "robin@example.org",
             # The date of the decision is the date in the organisation.
             ~D[2026-11-28],
             nil,
             nil,
             nil,
             2
           ]
  end
end
