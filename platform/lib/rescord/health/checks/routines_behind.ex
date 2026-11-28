defmodule Rescord.Health.Checks.RoutinesBehind do
  @moduledoc """
  C1 of issue 38: a routine whose tasks do not reach its horizon. The job
  of the tasks (`Rescord.Tasks.Workers.GenerateTasks`) moves the mark
  `generated_until` of each routine each hour, up to the end of the day
  that is `days_ahead` days ahead. It makes no task for a time before now
  (ADR 0033), so a routine whose mark is in the past has lost slots for
  good: a dose that nobody was asked to give. And the job logs the fault of
  an organisation and still ends well, so nothing else says so.

  A routine counts when it is not archived, not paused, not ended, and does
  not count from the last task (such a routine has one task at a time). It
  is a note when its mark is more than a day short of its horizon, and a
  fault when the mark is before now. The ids are those of the routines.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :routines_behind
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "Routines whose tasks run out"

  @impl true
  def explain,
    do:
      "A fault: a routine has no task for a time that has come, so a member was not asked " <>
        "to do it. A note: its tasks end more than a day before they should. Look at the log " <>
        "of the job of the tasks, then open the routine."

  @impl true
  def run(%{organisation: organisation, now: now} = context) do
    routines = table(context, "routines")
    today = Rescord.Accounts.local_date(organisation, now)

    behind = """
    select r.id from #{routines} r
    where r.archived_at is null and not r.paused and r.count_from <> 'last_done'
      and (r.ends_on is null or r.ends_on >= $2::date)
      and (r.generated_until is null
        or r.generated_until < $1::timestamp
          + make_interval(days => coalesce(r.days_ahead, $3)::int) - interval '1 day')
    """

    params = [DateTime.to_naive(now), today, organisation.task_days_ahead]

    case query(
           behind <> " and (r.generated_until is null or r.generated_until < $1::timestamp)",
           params
         ) do
      {0, _ids} -> behind |> query(params) |> found(:note)
      lost -> found(lost, :fail)
    end
  end
end
