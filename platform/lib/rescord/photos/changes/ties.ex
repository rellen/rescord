defmodule Rescord.Photos.Changes.Ties do
  @moduledoc """
  What `Rescord.Photos.Changes.EndPhotoTies` and
  `Rescord.Photos.Changes.EndAlbumTies` share: the options of the reads and
  the removals of the ties, and the removals themselves.
  """

  @doc """
  The options of a tie that a removal ends: the tenant and the instant of
  the action, and its actor for the paper trail, with no second decision of
  a policy.
  """
  def options(changeset, context) do
    base = [actor: context.actor, tenant: changeset.tenant, authorize?: false]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end

  @doc "Runs each removal of `{tie, action}`, and stops at the first error."
  def finish(ties, record, options) do
    Enum.reduce_while(ties, {:ok, record}, fn {tie, action}, done ->
      case Ash.destroy(tie, [action: action] ++ options) do
        :ok -> {:cont, done}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
