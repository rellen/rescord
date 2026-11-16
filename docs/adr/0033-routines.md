# ADR 0033: Routines

Status: accepted (the answer is from the maintainer, 16 November 2026)

## Context

Section 5.7 of `docs/domain.md` gives a task that repeats: a routine. It
repeats each day at set times, on given days of the week, or after a number
of days.

The maintainer answered how far ahead the tasks of a routine exist: "N days
ahead, default 14, but some things could be like a calendar, recurring or
one-off events/tasks planned potentially months ahead".

## Decision

- **A routine makes tasks.** `Rescord.Tasks.Routine` holds what to do, for
  which residents, groups and locations, and when. Rescord makes a
  `Rescord.Tasks.Task` for each time of the routine. A member works with
  those tasks as with each other task. A task names its routine.
- **Four patterns**: each day; on given days of the week; every number of
  days, from the first day of the routine; every number of months, on the
  day of the month of the first day. The last one is for the calendar: a
  check each 3 months, or each year. `Rescord.Tasks.Pattern` gives the days
  of a pattern, with no database and no clock.
- **A routine has from 1 to 12 times of the day**, a first day, and a last
  day or none. The days and the times are those of the organisation, in its
  time zone. For a time that the clocks skip, the task is at the first
  instant after the gap. For a time that comes two times, it is at the first
  one.
- **The tasks exist a number of days ahead.** The organisation has the
  setting `task_days_ahead`, which is 14 at first. An administrator changes
  it on the settings page, from 1 to 400. A routine can have a number of its
  own, so a routine of each year has its next task in the calendar. The
  horizon is the end of the day that is that number of days after today.
- **`generated_until` on the routine is the instant up to which its tasks
  exist.** `Rescord.Tasks.Changes.SyncTasks` makes the tasks from that
  instant to the horizon, and moves the instant, in one transaction with a
  lock on the routine. It runs when a routine starts, when a member changes
  it, and each hour in the job `Rescord.Tasks.Workers.GenerateTasks`. So no
  task is made two times. A time that has a task of the routine gets no
  second one.
- **No task is made for a time before now**: not after a pause, and not
  after a time when the job did not run.
- **A change to a routine makes its coming tasks again.** Rescord cancels
  the tasks of the routine that are due after now, and makes them from the
  new facts. A pause cancels them, and so does the end of the routine. The
  tasks that are done, skipped or late stay.
- **One run makes 500 tasks at most** for one routine. The next run makes
  the others.
- **A routine is not temporal.** Its mark moves each day, and a task names
  it with a key of the database. Its history is in its paper trail, which
  does not record the moves of the mark.
- **A routine names its subjects in three lists of ids**, and its kind, its
  member and its prescription by plain ids, as a task does. The database can
  hold no key to a temporal resource (ADR 0032).
- **A routine can name a prescription.** Each of its tasks then writes a
  dose to the journal when a member completes it. A member starts such a
  routine from the prescription, on the journal page.
- **Each member has each grant for a routine**, as for a task. No role has a
  grant for the actions that Rescord runs itself.
- The job runs each hour, because a day starts at a different hour in each
  time zone. A routine that has its tasks up to its horizon costs no write.

## Consequences

- "After a number of days" is every number of days from the first day of
  the routine. It is not a number of days after a member completed the last
  task. The maintainer can ask for that pattern.
- A change to a routine cancels a coming task that a member took. The new
  task is for the member that the routine names, or for each member.
- A change of the time zone of the organisation moves no task that exists.
  The tasks that the routine makes after the change are in the new zone.
- A smaller number of days ahead removes no task that exists.
- A member who looks at a day after the horizon sees no task of a routine
  there. The page does not show the tasks that the routine will make.
- A routine keeps a resident, a group or a location that is not there any
  more. Its tasks name that subject, and the page says that it is not here
  now.
- The form of the page has one resident, one group and one location, and 4
  times. The resource takes more.
