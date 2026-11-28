defmodule Rescord.Expenses.Changes.SetPayer do
  @moduledoc """
  Says who the organisation pays back for a new expense (ADR 0082).

  An expense that the organisation paid has no payer. An expense that a
  member paid names the user of the argument `payer_id`, which only `record`
  has, or the actor.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    payer =
      case Ash.Changeset.get_attribute(changeset, :paid_by) do
        :member -> given(changeset) || actor_id(context)
        _the_organisation -> nil
      end

    Ash.Changeset.force_change_attribute(changeset, :payer_id, payer)
  end

  defp given(changeset) do
    case Ash.Changeset.fetch_argument(changeset, :payer_id) do
      {:ok, id} when is_binary(id) -> id
      _none -> nil
    end
  end

  defp actor_id(%{actor: %Rescord.Accounts.User{id: id}}), do: id
  defp actor_id(_context), do: nil
end
