defmodule Rescord.Locations.Validations.NotInsideItself do
  @moduledoc """
  A location is not inside itself, directly or through other locations.
  Without this rule the ties could make a circle, and a walk from a location
  to the top would not end.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Locations.LocationParent

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, context) do
    location = Ash.Changeset.get_attribute(changeset, :location_id)
    parent = Ash.Changeset.get_attribute(changeset, :parent_id)

    cond do
      is_nil(location) or is_nil(parent) ->
        :ok

      location == parent ->
        {:error, field: :parent_id, message: "cannot be the location itself"}

      location in above(parent, MapSet.new(), options(changeset, context)) ->
        {:error, field: :parent_id, message: "is inside this location"}

      true ->
        :ok
    end
  end

  # Each location that contains `id`, to the top. `seen` stops the walk if
  # the ties hold a circle already.
  defp above(id, seen, options) do
    case LocationParent |> Ash.Query.filter(location_id == ^id) |> Ash.read_one!(options) do
      nil ->
        seen

      %{parent_id: parent} ->
        if MapSet.member?(seen, parent),
          do: seen,
          else: above(parent, MapSet.put(seen, parent), options)
    end
  end

  defp options(changeset, context) do
    base = [actor: context.actor, tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
