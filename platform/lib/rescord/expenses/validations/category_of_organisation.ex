defmodule Rescord.Expenses.Validations.CategoryOfOrganisation do
  @moduledoc """
  The category of an expense is a value of the list `expense category` of
  the organisation, and one that the list still offers. An expense keeps a
  category that the organisation retired afterwards: the validation looks
  only at a new expense and at a category that changes.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    if changeset.action_type == :create or
         Ash.Changeset.changing_attribute?(changeset, :category_id) do
      check(Ash.Changeset.get_attribute(changeset, :category_id), changeset, context)
    else
      :ok
    end
  end

  # Without a category the attribute says that it is required.
  defp check(nil, _changeset, _context), do: :ok

  defp check(id, changeset, context) do
    options = [tenant: changeset.tenant, actor: context.actor]

    with {:ok, values} <- Rescord.Lists.values(:expense_category, options),
         %{retired: false} <- Enum.find(values, &(&1.id == id)) do
      :ok
    else
      %{retired: true} ->
        {:error, field: :category_id, message: "is a category that the organisation uses no more"}

      _no_category ->
        {:error, field: :category_id, message: "is not a category of this organisation"}
    end
  end
end
