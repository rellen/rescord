defmodule Rescord.Lists.ExpenseCategory do
  @moduledoc """
  The values of the dimension `expense category` that one organisation uses:
  what an expense was for, such as a vet, food or transport (ADR 0082).
  """

  use Rescord.Lists.OrganisationList,
    table: "expense_categories",
    base: Rescord.Lists.Base.ExpenseCategory
end
