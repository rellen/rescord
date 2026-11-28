defmodule Rescord.Health.Checks.DepartedInCare do
  @moduledoc """
  C17 of issue 38: a resident who left and is still in the care of the
  organisation. A departure (ADR 0067) ends the placement of the resident,
  and takes the resident out of the routines and out of the tasks that are
  due. A departure from before ADR 0067 ended nothing, and a revision of a
  routine can name a resident who left. So a resident with a current
  departure counts when:

    * a current placement names the resident;
    * a routine that is not removed and has not ended names the resident;
    * a task that is due has the resident as a subject.

  An accepted transfer of a resident to another organisation, answered
  more than 7 days ago, whose resident has no departure in the organisation
  that sent it, counts too: the resident is in the care of both.

  The ids are those of the residents.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :departed_in_care
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Residents who left and are still in care"

  @impl true
  def explain,
    do:
      "A resident who left still has a place, a routine or a task that is due, or went to " <>
        "another refuge with a transfer and has no departure here. Open the resident: end the " <>
        "placement, take the resident out of the routine or the task, or record the departure."

  @impl true
  def run(%{organisation: organisation, now: now} = context) do
    today = Rescord.Accounts.local_date(organisation, now)

    """
    with departed as (
      select d.resident_id from #{table(context, "departures")} d
      where d.valid_at @> $1::timestamptz
    )
    select p.resident_id as id from #{table(context, "placements")} p
    where p.valid_at @> $1::timestamptz and p.resident_id in (select resident_id from departed)
    union
    select r.resident_id from (
      select unnest(ro.resident_ids) as resident_id from #{table(context, "routines")} ro
      where ro.archived_at is null and (ro.ends_on is null or ro.ends_on >= $2::date)
    ) r
    where r.resident_id in (select resident_id from departed)
    union
    select s.resident_id from #{table(context, "task_subjects")} s
    join #{table(context, "tasks")} t on t.id = s.task_id
    where s.archived_at is null and t.archived_at is null and t.state = 'due'
      and s.resident_id in (select resident_id from departed)
    union
    select tr.resident_id from #{table(%{prefix: nil}, "transfers")} tr
    where tr.from_organisation_id = $3::uuid and tr.state = 'accepted'
      and tr.answered_at < $4::timestamp - interval '7 days'
      and tr.resident_id is not null
      and tr.resident_id not in (select resident_id from departed)
    """
    |> query([now, today, Ecto.UUID.dump!(organisation.id), DateTime.to_naive(now)])
    |> found(:fail)
  end
end
