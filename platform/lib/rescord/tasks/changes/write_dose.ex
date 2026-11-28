defmodule Rescord.Tasks.Changes.WriteDose do
  @moduledoc """
  Writes a journal entry for the dose when a member completes a task that
  names a prescription (`docs/domain.md`, section 5.7). The entry is for the
  resident of the prescription, at the time that the task was completed. It
  records no stock movement.

  The entry is written as the actor, who is its author. A fault in it stops
  the completion: a task is not done with no record of the dose.
  """

  use Ash.Resource.Change

  alias Rescord.Journal
  alias Rescord.Tasks.Errors.NoPrescription

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, task ->
      case task.prescription_id do
        nil -> {:ok, task}
        prescription_id -> write(prescription_id, task, changeset, context.actor)
      end
    end)
  end

  defp write(prescription_id, task, changeset, actor) do
    # The entry and its details share the correlation id of the completion
    # (ADR 0100).
    options = [
      actor: actor,
      tenant: changeset.tenant,
      context: Rescord.Correlation.context(changeset)
    ]

    with {:ok, %{} = entry} <- Journal.entry_of_prescription(prescription_id, options),
         {:ok, _dose} <-
           Journal.write_entry(
             %{
               resident_id: entry.resident_id,
               kind: :dose,
               prescription_id: prescription_id,
               note: task.note || "From the task: #{task.title}",
               happened_at: task.finished_at
             },
             options
           ) do
      {:ok, task}
    else
      {:ok, nil} -> {:error, NoPrescription.exception()}
      {:error, error} -> {:error, error}
    end
  end
end
