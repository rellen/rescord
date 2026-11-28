defmodule Rescord.Health.Checks.RoutineAfterPrescription do
  @moduledoc """
  C2 of issue 38: a routine that gives the doses of a prescription, and
  does not end when the prescription ended. A routine of a prescription
  ends with it now (issue 38, F4), and makes no task after its end; a
  routine from before that, or a prescription whose end moved earlier
  after the routine started, still shows as running and can hold tasks
  after the end.

  The ids are those of the routines.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :routine_after_prescription
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Medication routines that outlive their prescription"

  @impl true
  def explain,
    do:
      "The prescription has ended, and its routine has not. Open the routine: end it on the " <>
        "last day of the prescription, and skip the tasks after it."

  @impl true
  def run(%{organisation: organisation, now: now} = context) do
    today = Rescord.Accounts.local_date(organisation, now)

    query(
      """
      select r.id from #{table(context, "routines")} r
      join #{table(context, "prescriptions")} p on p.id = r.prescription_id
        and p.valid_at @> $1::timestamptz and p.archived_at is null
      where r.archived_at is null and not r.paused
        and p.ends_on is not null and p.ends_on < $2::date
        and (r.ends_on is null or r.ends_on > p.ends_on)
      """,
      [now, today]
    )
    |> found(:fail)
  end
end
