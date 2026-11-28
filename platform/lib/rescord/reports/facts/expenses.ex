defmodule Rescord.Reports.Facts.Expenses do
  @moduledoc """
  The facts of the expenses of a period (ADR 0082): each expense that the
  person reads with a payment from the first day to the last day, and each
  expense that the organisation owes to a member now, on each day.

  A person who manages the expenses reads each one, and each other person
  reads their own: `all?` says which, so that the document says what it
  holds. `people` gives the email address of each member by the id of the
  user.
  """

  @behaviour Rescord.Reports.Facts

  alias Rescord.{Accounts, Expenses}
  alias Rescord.Reports.Facts

  @impl true
  def read(%{from: from, to: to}, options, _now) do
    if Date.compare(from, to) == :gt do
      {:error, Facts.invalid(:to, "is before the first day")}
    else
      with {:ok, expenses} <- Expenses.report(%{from: from, to: to}, options),
           {:ok, owed} <- Expenses.report(%{status: :to_pay_back}, options),
           {:ok, members} <- Accounts.members([load: [:email]] ++ options) do
        {:ok,
         %{
           from: from,
           to: to,
           expenses: expenses,
           owed: owed,
           all?: all?(options),
           reader: options[:actor],
           people: Map.new(members, &{&1.user_id, to_string(&1.email)})
         }}
      end
    end
  end

  # Whether the person reads each expense of the organisation.
  defp all?(options) do
    case Accounts.organisation_for(options[:actor], options[:tenant].short_name) do
      {:ok, _organisation, member} ->
        options[:actor] |> Accounts.role_in(member) |> Expenses.role_can?(:expense, :approve)

      :error ->
        false
    end
  end
end
