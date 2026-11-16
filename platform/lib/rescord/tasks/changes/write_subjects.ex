defmodule Rescord.Tasks.Changes.WriteSubjects do
  @moduledoc """
  Writes the subjects of a new task, from the arguments `resident_ids`,
  `group_ids` and `location_ids`: one `TaskSubject` for each id, after the
  task and in the same transaction.

  The policy of the task decided that the actor can plan it. The subjects
  are a part of that action, so the change writes them with no second
  decision, and names the actor for the paper trail.
  """

  use Ash.Resource.Change

  alias Rescord.Tasks.TaskSubject

  @arguments [resident_ids: :resident_id, group_ids: :group_id, location_ids: :location_id]

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, task ->
      options = [actor: context.actor, tenant: changeset.tenant, authorize?: false]

      subjects =
        for {argument, key} <- @arguments,
            id <- Enum.uniq(List.wrap(Ash.Changeset.get_argument(changeset, argument))) do
          %{key => id, task_id: task.id}
        end

      Enum.reduce_while(subjects, {:ok, task}, fn subject, done ->
        case TaskSubject |> Ash.Changeset.for_create(:add, subject, options) |> Ash.create() do
          {:ok, _subject} -> {:cont, done}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end)
  end
end
