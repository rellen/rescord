defmodule Rescord.Expenses.Changes.SetAmount do
  @moduledoc """
  Makes the amount of an expense from the number of the argument `amount`
  (ADR 0082).

  No action takes a currency. A new expense is in the currency of the
  organisation, and a change keeps the currency that the expense has. The
  number is more than zero, less than 100 million, and has no more decimal
  places than the currency has: two for a dollar, none for a yen.

  With no argument, as in a change that leaves the amount alone, the change
  does nothing.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts

  @limit Decimal.new("100000000")

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :amount) do
      {:ok, %Decimal{} = number} -> set(changeset, number, currency(changeset))
      _no_number -> changeset
    end
  end

  # The currency of the expense, or of the organisation for a new one.
  defp currency(%{data: %{amount: %Money{currency: currency}}}), do: currency
  defp currency(changeset), do: Accounts.currency_of(changeset.to_tenant)

  defp set(changeset, number, currency) do
    with :ok <- positive(number),
         :ok <- below_limit(number),
         :ok <- places(number, Accounts.currency_digits(currency), currency),
         %Money{} = amount <- Money.new(currency, number) do
      Ash.Changeset.force_change_attribute(changeset, :amount, Money.round(amount))
    else
      {:error, words} when is_binary(words) -> error(changeset, words)
      _not_money -> error(changeset, "is not an amount in #{currency}")
    end
  end

  defp positive(number) do
    if Decimal.positive?(number), do: :ok, else: {:error, "must be more than zero"}
  end

  defp below_limit(number) do
    if Decimal.compare(number, @limit) == :lt,
      do: :ok,
      else: {:error, "must be less than 100 million"}
  end

  # `12.50` has two places, and `12.500` has one that counts: the zeros at
  # the end are no part of the amount.
  defp places(number, digits, currency) do
    if Decimal.scale(Decimal.normalize(number)) <= digits do
      :ok
    else
      {:error, "has more decimal places than #{currency} has: #{digits} at most"}
    end
  end

  defp error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :amount, message: message)
end
