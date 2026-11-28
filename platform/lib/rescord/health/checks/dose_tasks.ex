defmodule Rescord.Health.Checks.DoseTasks do
  @moduledoc """
  C3 of issue 38: a task that gives a dose and cannot be done, or that is
  long overdue.

  - A fault: a due task whose prescription, or the journal entry of that
    prescription, is not current. Done writes the dose to the journal
    (`Rescord.Tasks.Changes.WriteDose`), which refuses it, so a member can
    only skip the task. `tasks.prescription_id` has no foreign key.
  - A note: a due task that gives a dose and was due more than 12 hours
    ago. Late work stays on the list by design (ADR 0033), and a dose that
    late needs somebody to decide.

  The ids are those of the tasks.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :dose_tasks
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Medication tasks that cannot be done, or are long overdue"

  @impl true
  def explain,
    do:
      "A fault: the prescription of a due medication task was removed, so Done is refused. " <>
        "Skip the task, and look at the routine. A note: a medication task is more than 12 " <>
        "hours late: decide whether to give the dose or to skip it."

  @impl true
  def run(%{now: now} = context) do
    tasks = table(context, "tasks")

    cannot =
      query(
        """
        select t.id from #{tasks} t
        where t.state = 'due' and t.archived_at is null and t.prescription_id is not null
          and not exists (
            select 1 from #{table(context, "prescriptions")} p
            join #{table(context, "journal_entries")} e on e.id = p.entry_id
              and e.valid_at @> $1::timestamptz and e.archived_at is null
            where p.id = t.prescription_id
              and p.valid_at @> $1::timestamptz and p.archived_at is null)
        """,
        [now]
      )

    case cannot do
      {0, _ids} ->
        query(
          """
          select t.id from #{tasks} t
          where t.state = 'due' and t.archived_at is null and t.prescription_id is not null
            and t.due_at < $1::timestamp - interval '12 hours'
          """,
          [DateTime.to_naive(now)]
        )
        |> found(:note)

      faults ->
        found(faults, :fail)
    end
  end
end
