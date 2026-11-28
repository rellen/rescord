defmodule Rescord.Expenses.Validations.ExpenseOpen do
  @moduledoc """
  A person takes off a receipt that they added only while its expense waits
  for a decision, or after it was declined. A decided expense keeps what the
  decision was made on. `discard`, for a person who manages the expenses,
  has no such rule.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Expenses.Expense

  @impl true
  def validate(changeset, _opts, context) do
    Expense
    |> Ash.Query.filter(id == ^changeset.data.expense_id)
    |> Ash.read_one(tenant: changeset.tenant, actor: context.actor)
    |> case do
      {:ok, %Expense{state: state}} when state in [:submitted, :declined] ->
        :ok

      _decided ->
        {:error,
         field: :expense_id,
         message: "is decided: only a person who manages the expenses takes a receipt off it"}
    end
  end
end
