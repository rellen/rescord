defmodule Rescord.Expenses.Changes.SetTax do
  @moduledoc """
  Makes the tax of an expense from the number of the argument `tax`
  (ADR 0089): the part of the amount that is tax, as the receipt shows it.

  No action takes a currency. The tax is in the currency of the amount. The
  number is zero or more, not more than the amount, and has no more decimal
  places than the currency has. Zero says that the receipt shows no tax.
  The argument with no value takes the tax off the expense.

  An organisation records a tax only while it names one in its settings
  (`Rescord.Accounts.tax_name_of/1`): with no name, a tax is refused.

  With no argument, the change leaves the tax alone, and checks only that an
  amount which changed is not less than the tax.

  Rescord knows no rate. It checks nothing else about the number.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :tax) do
      {:ok, %Decimal{} = number} -> set(changeset, number)
      {:ok, nil} -> Ash.Changeset.force_change_attribute(changeset, :tax, nil)
      _no_argument -> within_amount(changeset)
    end
  end

  defp set(changeset, number) do
    with %Money{currency: currency} = amount <- Ash.Changeset.get_attribute(changeset, :amount),
         :ok <- named(changeset),
         :ok <- not_negative(number),
         :ok <- places(number, Accounts.currency_digits(currency), currency),
         %Money{} = tax <- Money.new(currency, number),
         :ok <- not_more(tax, amount) do
      Ash.Changeset.force_change_attribute(changeset, :tax, Money.round(tax))
    else
      {:error, words} when is_binary(words) -> error(changeset, words)
      # The amount has an error of its own.
      nil -> changeset
      _not_money -> error(changeset, "is not an amount")
    end
  end

  # An amount that a person made smaller is still not less than the tax.
  defp within_amount(changeset) do
    with true <- Ash.Changeset.changing_attribute?(changeset, :amount),
         %Money{} = tax <- changeset.data.tax,
         %Money{} = amount <- Ash.Changeset.get_attribute(changeset, :amount),
         {:error, words} <- not_more(tax, amount) do
      error(changeset, words)
    else
      _fine -> changeset
    end
  end

  defp named(changeset) do
    if Accounts.tax_name_of(changeset.to_tenant),
      do: :ok,
      else: {:error, "is not recorded: the organisation names no tax in its settings"}
  end

  defp not_negative(number) do
    if Decimal.negative?(number), do: {:error, "must be zero or more"}, else: :ok
  end

  defp not_more(tax, amount) do
    if Money.compare!(tax, amount) == :gt,
      do: {:error, "must not be more than the amount"},
      else: :ok
  end

  # `1.50` has two places, and `1.500` has one that counts.
  defp places(number, digits, currency) do
    if Decimal.scale(Decimal.normalize(number)) <= digits do
      :ok
    else
      {:error, "has more decimal places than #{currency} has: #{digits} at most"}
    end
  end

  defp error(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :tax, message: message)
end
