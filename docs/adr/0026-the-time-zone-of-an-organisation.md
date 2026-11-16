# ADR 0026: The time zone of an organisation is a setting

Status: accepted (chosen by the maintainer, 16 November 2026)

## Context

ADR 0025 left Rescord with no time zone. Today was the date in UTC, and a
date of an arrival could be one day after it, so that a morning in Australia
was not refused. The age of a resident and the dates of its history were in
UTC too. For the first ten hours of a day in Brisbane, each was the day
before.

The maintainer decided that the time zone is a setting of the organisation,
and chose two things: the package `tz` for the rules, and who sets the zone.
Elixir has no time zone rules of its own.

## Decision

- **An organisation has a time zone**, in the attribute `time_zone`: a name
  of the IANA database, for example `Australia/Brisbane`. It is necessary.
- **A root user gives the zone when they create the organisation.** An
  administrator of the organisation, and a root user, change it on the
  settings page, `/o/<short name>/settings`. A member reads it.
- **`tz` is a dependency.** It has the rules in its code, and downloads
  nothing while Rescord runs. `config :elixir, :time_zone_database` names
  it. A name is a time zone when `tz` knows it.
- The suggestions of a form come from the list of PostgreSQL,
  `pg_timezone_names`, because `tz` gives no list. Each suggestion is a name
  that `tz` knows.
- `Rescord.Accounts.today/1` and `local_date/2` give the date in an
  organisation. They take the organisation, or the name of its schema, as
  an action has it.
- **A date of an arrival or a departure is not after today in the
  organisation.** The day of tolerance of ADR 0025 is gone. The page of a
  resident counts the age to that date, and shows the dates of its history
  in that zone.
- An administrator changes the zone through the grant
  `{Organisation, :set_time_zone, :all}`. An organisation is outside the
  schemas, so the check `Rescord.Accounts.Checks.GrantedInOrganisation`
  reads the role of the actor in the organisation that the action changes.
- An organisation that was there before this record gets `Etc/UTC` from the
  migration. Its administrator then sets the real zone.

## Consequences

- New rules of a zone, for example a change to summer time, come with a new
  release of `tz`. Read its changes when you update it.
- A change of the zone changes what today is from then on. It does not
  change a date that Rescord stored: a date has no zone.
- An instant is still stored in UTC. Only a page turns it into a local date.
- The page of a resident shows a date, and no time of day, so no page turns
  an instant into a local time yet.
