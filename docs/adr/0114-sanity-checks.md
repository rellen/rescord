# ADR 0114: Sanity checks that run on their own, change nothing, and say what they find

Status: accepted. The maintainer asked on 28 November 2026 whether
Rescord could run periodic sanity checks of its data and of the server.
Issue 38 is the design, from a read of the code by area on that day. The
maintainer chose "Both builds": the runner and the checks C1 to C23 with
the fixes F1 to F6, and the judgement calls of section 11 as written.

## Context

`bin/check` (ADR 0049) checks a server before it goes live, and
`bin/check-files` (ADR 0091) compares the store with the database by
hand. `/health` runs `select 1`. Nothing checked the data on a schedule,
and the server had no way to tell an operator about a fault but the log
and the metrics (ADR 0077). The read found invariants that only an Ash
validation holds, or nothing, and states that can last for ever with no
sign: a routine whose tasks ran out, a reply of the assistant that stays
`streaming`, a job that stopped.

## Decision

1. **A check is a module of `Rescord.Health.Checks`** with a name, a
   scope (the server, or each organisation), a cadence (hourly, daily,
   weekly), words for the page, and `run/1`, which gives a level (`ok`,
   `note`, `fail`), a count, and at most 20 ids. A result never holds a
   value of a row.
2. **Read-only by PostgreSQL.** Each run of a check is one transaction
   that starts with `SET TRANSACTION READ ONLY`, a `statement_timeout` of
   10 seconds (a check may ask for more) and a `lock_timeout` of 1 second,
   and that `Rescord.Health.run/2` rolls back. A check that raises or runs
   out of time is `unknown`; three in a row are `fail`.
3. **SQL, not Ash actions.** A check reads the tables with SQL and the
   schema of the organisation. It looks for rows that the policies, the
   default filters and the validations are there to stop, and an action
   would hide them.
4. **One runner.** `Rescord.Health.Workers.Run` starts each hour at
   minute 47, in the queue `health` of one job, with one try. A check is
   due when its oldest result is older than its period less 10 minutes, so
   a missed hour does not skip a daily check. It does not wait for a set
   hour of the day.
5. **One row for each check and scope** in `health_results`, written in
   place, with no paper trail: the level, the count, the ids, `since` (the
   time the level changed), the last run and its time. A change of level
   writes one log line with the check, the level and the count.
6. **Where it shows.** `/root/health` for root users, a line on `/root`,
   a line of `bin/check` (a fault when a check fails, or when the newest
   run is older than 3 hours, so a stopped runner is seen), and the gauge
   `rescord.health.level`, tagged by the name of the check only.

## Consequences

- A new check is a module and a name in `Rescord.Health.Checks`. The list
  of names is a literal, because the attribute `check` of the result
  names them when it compiles; a test holds the two lists together.
- A check that a newer version takes out leaves rows: the runner deletes
  them.
- The checks of the cron read the crontab of the config, so a new hourly
  job is checked with no change to the check.
- The first run after an upgrade may report faults that were there before
  it. The upgrade note says so.
- A check is not a fix. A fault that a check finds is put right by a
  person, or by a fix at the source (issue 38, section 7).
