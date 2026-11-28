defmodule Rescord.Inventory.Changes.MoveIn do
  @moduledoc """
  Writes the movement in of a move, after the movement out and in the same
  transaction: the same quantity of the same lot comes into the place of
  the argument `to_location_id`.

  The two places are not the same place. The policy of the movement out
  decided that the actor can move stock, so the change writes the movement
  in with no second decision, and names the actor as its author.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Rescord.Inventory.StockMovement

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    to = Changeset.get_argument(changeset, :to_location_id)

    if to == Changeset.get_attribute(changeset, :location_id) do
      Changeset.add_error(changeset,
        field: :to_location_id,
        message: "is the place that the stock is in"
      )
    else
      Changeset.after_action(changeset, fn changeset, out ->
        StockMovement
        |> Changeset.for_create(
          :move_in,
          %{
            lot_id: out.lot_id,
            location_id: to,
            happened_at: out.happened_at,
            note: out.note,
            quantity: Decimal.negate(out.quantity)
          },
          actor: context.actor,
          tenant: changeset.tenant,
          context: Map.take(changeset.context, [:shared]),
          authorize?: false
        )
        |> Ash.create()
        |> case do
          {:ok, _in} -> {:ok, out}
          {:error, error} -> {:error, error}
        end
      end)
    end
  end
end
