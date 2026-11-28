defmodule Rescord.Expenses.PaidBy do
  @moduledoc """
  Who paid an expense (ADR 0082):

    * `:member` - a member paid with their own money, and the organisation
      pays that member back;
    * `:organisation` - the organisation paid, for example with its own
      card or from its account.

  A page shows the words of `RescordWeb.ExpenseWords`, and never the atom.
  """

  use Ash.Type.Enum, values: [:member, :organisation]
end
