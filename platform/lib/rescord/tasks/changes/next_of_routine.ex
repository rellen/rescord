defmodule Rescord.Tasks.Changes.NextOfRoutine do
  @moduledoc """
  Makes the tasks of the next day of a routine that counts its days from the
  last task (ADR 0039), when a member completes or skips one of its tasks.

  The change runs `generate` of the routine after the action, in the same
  transaction. `Rescord.Tasks.Changes.SyncTasks` makes nothing while a task
  of the routine is due, so the last task of a day makes the next day. A
  task of another routine, and a task with no routine, change nothing.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Tasks.Routine

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, task ->
      internal = [
        tenant: changeset.tenant,
        context: Map.take(changeset.context, [:shared]),
        authorize?: false
      ]

      with routine_id when is_binary(routine_id) <- task.routine_id,
           {:ok, %Routine{pattern: :interval, count_from: :last_done} = routine} <-
             Routine |> Ash.Query.filter(id == ^routine_id) |> Ash.read_one(internal),
           {:ok, _routine} <-
             routine
             |> Ash.Changeset.for_update(:generate, %{}, [actor: context.actor] ++ internal)
             |> Ash.update() do
        {:ok, task}
      else
        {:error, error} -> {:error, error}
        _no_such_routine -> {:ok, task}
      end
    end)
  end
end
