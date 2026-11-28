defmodule Rescord.Residents.Changes.JoinGroup do
  @moduledoc """
  Makes the first members of a new group: one `GroupMember` for each id of
  the argument `resident_ids`, after the group, in the same transaction and
  as of the same instant.

  The policy of the group decided that the actor can make it. The members
  are a part of that action, so the change writes them with no second
  decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  alias Rescord.Residents.GroupMember

  # The change writes through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, group ->
      base = [
        actor: context.actor,
        tenant: changeset.tenant,
        context: Rescord.Correlation.context(changeset),
        authorize?: false
      ]

      options =
        case changeset.as_of do
          %DateTime{} = instant -> [as_of: instant] ++ base
          _not_set -> base
        end

      changeset
      |> Ash.Changeset.get_argument(:resident_ids)
      |> List.wrap()
      |> Enum.uniq()
      |> Enum.reduce_while({:ok, group}, fn resident_id, done ->
        GroupMember
        |> Ash.Changeset.for_create(
          :join,
          %{resident_id: resident_id, group_id: group.id},
          options
        )
        |> Ash.create()
        |> case do
          {:ok, _member} -> {:cont, done}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end
end
