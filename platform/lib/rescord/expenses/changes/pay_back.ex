defmodule Rescord.Expenses.Changes.PayBack do
  @moduledoc """
  Records who said that the organisation paid a member back: the actor. The
  date of the payment is today in the organisation when the person gives
  none. Rescord sends no money.
  """

  use Ash.Resource.Change

  alias Rescord.Accounts

  @impl true
  def change(changeset, _opts, context) do
    by = if match?(%Rescord.Accounts.User{}, context.actor), do: context.actor.id
    changeset = Ash.Changeset.force_change_attribute(changeset, :reimbursed_by_id, by)

    if Ash.Changeset.get_attribute(changeset, :reimbursed_on) do
      changeset
    else
      Ash.Changeset.force_change_attribute(
        changeset,
        :reimbursed_on,
        Accounts.today(changeset.to_tenant)
      )
    end
  end
end
