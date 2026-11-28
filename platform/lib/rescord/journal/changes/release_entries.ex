defmodule Rescord.Journal.Changes.ReleaseEntries do
  @moduledoc """
  Takes the condition off each journal entry that is about an episode, when
  a person removes that episode (ADR 0083). The change does so before the
  removal, in the same transaction and as of the same instant, so each
  entry stays in the journal, about no condition.

  Without it an entry names an episode that no page can read: its diagnosis
  can not start the condition again, and the export has an id of a record
  that is not there.

  The policy of the episode decided that the actor can remove it. The
  entries are a part of that action, so the change writes them with no
  second decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Journal.JournalEntry

  # The change reads and writes through Ash only, as of the instant of the action.
  @impl true
  def temporal_safe?(_opts), do: true

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      options = options(changeset, context)
      id = changeset.data.id

      JournalEntry
      |> Ash.Query.filter(episode_id == ^id)
      |> Ash.read!(options)
      |> Enum.reduce_while(changeset, fn entry, changeset ->
        case entry
             |> Ash.Changeset.for_update(:release, %{}, options)
             |> Ash.update() do
          {:ok, _entry} -> {:cont, changeset}
          {:error, error} -> {:halt, Ash.Changeset.add_error(changeset, error)}
        end
      end)
    end)
  end

  defp options(changeset, context) do
    base = [
      actor: context.actor,
      tenant: changeset.tenant,
      context: Rescord.Correlation.context(changeset),
      authorize?: false
    ]

    case changeset.as_of do
      %DateTime{} = instant -> [as_of: instant] ++ base
      _not_set -> base
    end
  end
end
