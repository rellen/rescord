defmodule Rescord.Expenses.Validations.PayerIsMember do
  @moduledoc """
  The person whom the organisation pays back is a member of the
  organisation. `record` names that person in the argument `payer_id`; with
  none, the payer is the actor, who is a member already.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, context) do
    with :member <- Ash.Changeset.get_attribute(changeset, :paid_by),
         {:ok, id} when is_binary(id) <- Ash.Changeset.fetch_argument(changeset, :payer_id) do
      case Rescord.Accounts.members(tenant: changeset.tenant, actor: context.actor) do
        {:ok, members} ->
          if Enum.any?(members, &(&1.user_id == id)),
            do: :ok,
            else: {:error, field: :payer_id, message: "is not a member of this organisation"}

        {:error, _error} ->
          {:error, field: :payer_id, message: "is not a member of this organisation"}
      end
    else
      _no_payer_to_check -> :ok
    end
  end
end
