defmodule Rescord.Residents.Changes.EndTies do
  @moduledoc """
  Ends the ties of a resident that an administrator removes: each group it
  is in, each family it is in, and each link to a parent or to a young one.
  The change ends them after the removal, in the same transaction and as of
  the same instant, so their history stays.

  Without it a removed resident stays a member of its groups and the parent
  of its young ones, and each page that names the members of a group or the
  relatives of a resident finds a member that it cannot read.

  The policy of the resident decided that the actor can remove it. The ties
  are a part of that action, so the change ends them with no second
  decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Residents.{FamilyMember, GroupMember, ParentLink}

  # The change reads and writes through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, resident ->
      options = options(changeset, context)
      id = resident.id

      groups = GroupMember |> Ash.Query.filter(resident_id == ^id) |> Ash.read!(options)
      families = FamilyMember |> Ash.Query.filter(resident_id == ^id) |> Ash.read!(options)

      links =
        ParentLink
        |> Ash.Query.filter(resident_id == ^id or parent_id == ^id)
        |> Ash.read!(options)

      ties =
        Enum.map(groups, &{&1, :leave}) ++
          Enum.map(families, &{&1, :remove}) ++ Enum.map(links, &{&1, :remove})

      Enum.reduce_while(ties, {:ok, resident}, fn {tie, action}, done ->
        case Ash.destroy(tie, [action: action] ++ options) do
          :ok -> {:cont, done}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end

  defp options(changeset, context) do
    base = [actor: context.actor, tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
