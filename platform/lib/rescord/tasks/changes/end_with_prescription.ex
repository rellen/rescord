defmodule Rescord.Tasks.Changes.EndWithPrescription do
  @moduledoc """
  A routine that gives the doses of a prescription ends when the
  prescription ends (issue 38, F4): when the prescription has a last day,
  the routine ends on that day at the latest. A routine with no end, or one
  that ends later, gets the last day of the prescription.

  `Rescord.Tasks.Changes.SyncTasks` holds to the same day when it makes the
  tasks, so a prescription whose end moves earlier after the routine
  started gets no task after its new end either.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    prescription_id =
      Ash.Changeset.get_attribute(changeset, :prescription_id) ||
        Map.get(changeset.data, :prescription_id)

    with id when is_binary(id) <- prescription_id,
         {:ok, %Date{} = last} <- Rescord.Journal.prescription_ends_on(id, changeset.tenant) do
      case Ash.Changeset.get_attribute(changeset, :ends_on) do
        %Date{} = ends_on ->
          if Date.after?(ends_on, last),
            do: Ash.Changeset.force_change_attribute(changeset, :ends_on, last),
            else: changeset

        nil ->
          Ash.Changeset.force_change_attribute(changeset, :ends_on, last)
      end
    else
      _no_end -> changeset
    end
  end
end
