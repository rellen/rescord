defmodule Rescord.Residents.Validations.ParentIsNotYoung do
  @moduledoc """
  A parent of a resident is another resident, and it is not one of the young
  of that resident, at any distance. Without this rule the parent links
  could make a circle, and a walk from young to parent would not end.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Residents.ParentLink

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, context) do
    young = Ash.Changeset.get_attribute(changeset, :resident_id)
    parent = Ash.Changeset.get_attribute(changeset, :parent_id)

    cond do
      is_nil(young) or is_nil(parent) ->
        :ok

      young == parent ->
        {:error, field: :parent_id, message: "cannot be the resident itself"}

      young in ancestors([parent], MapSet.new(), options(changeset, context)) ->
        {:error, field: :parent_id, message: "is one of the young of this resident"}

      true ->
        :ok
    end
  end

  # Each parent of the residents in `ids`, and their parents, to the top.
  # `seen` stops the walk if the links hold a circle already.
  defp ancestors([], seen, _options), do: seen

  defp ancestors(ids, seen, options) do
    parents =
      ParentLink
      |> Ash.Query.filter(resident_id in ^ids)
      |> Ash.read!(options)
      |> Enum.map(& &1.parent_id)
      |> Enum.reject(&MapSet.member?(seen, &1))
      |> Enum.uniq()

    ancestors(parents, MapSet.union(seen, MapSet.new(parents)), options)
  end

  defp options(changeset, context) do
    base = [actor: context.actor, tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
