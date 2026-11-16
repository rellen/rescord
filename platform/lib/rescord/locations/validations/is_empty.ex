defmodule Rescord.Locations.Validations.IsEmpty do
  @moduledoc """
  A location that is closed holds no resident, no group and no other
  location.

  Without this rule a resident in a closed location has a placement that
  names a location that nobody can read: the housing loses the resident,
  and its page has a home with no location. A location inside a closed one
  moves to the top of the housing with no word about it.

  A placement of a resident or a group that is not there any more does not
  count. The validation runs after the policy, so a person who cannot close
  a location gets the answer of the policy.
  """

  use Ash.Resource.Validation

  require Ash.Query

  alias Rescord.Locations.{LocationParent, Placement}

  # The validation reads through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def validate(changeset, _opts, _context) do
    id = changeset.data.id
    options = options(changeset)

    placed =
      Placement
      |> Ash.Query.filter(location_id == ^id)
      |> Ash.Query.load([:resident, :group])
      |> Ash.read!(options)
      |> Enum.any?(&(&1.resident || &1.group))

    inside =
      LocationParent
      |> Ash.Query.filter(parent_id == ^id)
      |> Ash.Query.load(:location)
      |> Ash.read!(options)
      |> Enum.any?(& &1.location)

    cond do
      placed ->
        {:error, field: :location, message: "has residents or groups in it. Move them first"}

      inside ->
        {:error, field: :location, message: "has other locations in it. Move them first"}

      true ->
        :ok
    end
  end

  defp options(changeset) do
    base = [tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
