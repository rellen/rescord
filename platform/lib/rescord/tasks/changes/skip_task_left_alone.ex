defmodule Rescord.Tasks.Changes.SkipTaskLeftAlone do
  @moduledoc """
  Skips a task that lost its only subject (ADR 0067): after a subject is
  taken out because its resident was removed, a task that is due and has no
  subject left is skipped, with a reason that says so.

  A task that has another resident, a group or a location stays due. A task
  that is done or skipped stays as it is. A member can open the task again.

  The change runs after the subject is archived, in the transaction of the
  removal. The removal was the decision, so the task is read and skipped
  with no authorization. The person who removed the resident is the person
  who finished the task.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Tasks.{Task, TaskSubject}

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, subject ->
      internal = [
        tenant: changeset.tenant,
        context: Map.take(changeset.context, [:shared]),
        authorize?: false
      ]

      with {:ok, %Task{state: :due} = task} <-
             Task |> Ash.Query.filter(id == ^subject.task_id) |> Ash.read_one(internal),
           {:ok, false} <-
             TaskSubject |> Ash.Query.filter(task_id == ^task.id) |> Ash.exists(internal),
           {:ok, _task} <-
             task
             |> Ash.Changeset.for_update(
               :skip_left_alone,
               %{},
               [actor: context.actor] ++ internal
             )
             |> Ash.update() do
        {:ok, subject}
      else
        # Another member finished the task a moment before: it stays as it is.
        {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Changes.StaleRecord{}]}} -> {:ok, subject}
        {:error, error} -> {:error, error}
        _stays -> {:ok, subject}
      end
    end)
  end
end
