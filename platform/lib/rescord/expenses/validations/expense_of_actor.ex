defmodule Rescord.Expenses.Validations.ExpenseOfActor do
  @moduledoc """
  A receipt names an expense of the organisation, and one that the actor can
  read: their own, or any for a person who manages the expenses. The
  validation runs after the policy, so a person with no grant gets the
  answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Expenses.Expense

  @impl true
  def validate(changeset, _opts, context) do
    with expense_id when is_binary(expense_id) <-
           Ash.Changeset.get_attribute(changeset, :expense_id),
         {:ok, %Expense{}} <-
           Expense
           |> Ash.Query.filter(id == ^expense_id)
           |> Ash.read_one(tenant: changeset.tenant, actor: context.actor) do
      :ok
    else
      _no_expense -> {:error, field: :expense_id, message: "is not an expense that you can read"}
    end
  end
end
