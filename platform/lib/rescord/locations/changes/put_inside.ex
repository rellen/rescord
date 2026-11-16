defmodule Rescord.Locations.Changes.PutInside do
  @moduledoc """
  Puts a new location inside the location that the argument `parent_id`
  names: it writes the tie after the location, in the same transaction and
  as of the same instant. With no `parent_id`, the location is inside none.

  The policy of the location decided that the actor can add it. The tie is a
  part of that action, so the change writes it with no second decision, and
  names the actor for the paper trail.
  """

  use Ash.Resource.Change

  alias Rescord.Locations.LocationParent

  # The change writes through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, location ->
      case Ash.Changeset.get_argument(changeset, :parent_id) do
        nil ->
          {:ok, location}

        parent_id ->
          base = [actor: context.actor, tenant: changeset.tenant, authorize?: false]

          options =
            case changeset.as_of do
              %DateTime{} = instant -> [as_of: instant] ++ base
              _not_set -> base
            end

          LocationParent
          |> Ash.Changeset.for_create(
            :put_inside,
            %{location_id: location.id, parent_id: parent_id},
            options
          )
          |> Ash.create()
          |> case do
            {:ok, _tie} -> {:ok, location}
            {:error, error} -> {:error, error}
          end
      end
    end)
  end
end
