defmodule Rescord.Inventory.Changes.FirstStock do
  @moduledoc """
  Writes the first stock movement of a new lot, after the lot and in the
  same transaction: the argument `quantity` came into the place of the
  argument `location_id`, at the time of the argument `happened_at`.

  The policy of the lot decided that the actor can receive stock, so the
  change writes the movement with no second decision, and names the actor
  as its author. A fault in the movement stops the lot.
  """

  use Ash.Resource.Change

  alias Ash.Changeset
  alias Rescord.Inventory.StockMovement

  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Changeset.after_action(changeset, fn changeset, lot ->
      StockMovement
      |> Changeset.for_create(
        :receive,
        %{
          lot_id: lot.id,
          location_id: Changeset.get_argument(changeset, :location_id),
          happened_at: Changeset.get_argument(changeset, :happened_at),
          quantity: Changeset.get_argument(changeset, :quantity)
        },
        actor: context.actor,
        tenant: changeset.tenant,
        context: Rescord.Correlation.context(changeset),
        authorize?: false
      )
      |> Ash.create()
      |> case do
        {:ok, _movement} -> {:ok, lot}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
