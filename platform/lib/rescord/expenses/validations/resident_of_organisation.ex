defmodule Rescord.Expenses.Validations.ResidentOfOrganisation do
  @moduledoc """
  The resident of an expense is a resident of the organisation that the
  actor can read. The validation looks only at a new expense and at a
  resident that changes: an expense keeps a resident that left the records.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    id = Ash.Changeset.get_attribute(changeset, :resident_id)

    cond do
      is_nil(id) ->
        :ok

      changeset.action_type == :create or
          Ash.Changeset.changing_attribute?(changeset, :resident_id) ->
        case Rescord.Residents.resident(id, tenant: changeset.tenant, actor: context.actor) do
          {:ok, %{}} ->
            :ok

          _no_resident ->
            {:error, field: :resident_id, message: "is not a resident of this organisation"}
        end

      true ->
        :ok
    end
  end
end
