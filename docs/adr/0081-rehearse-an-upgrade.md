# ADR 0081: A start rehearses the upgrade before it changes anything

Status: accepted (the maintainer asked for it on 28 November 2026, as the
follow-up of ADR 0073). The design is in issue 13.

## Context

A start of a new version runs each migration that has not run: those of
the database, then those of each organisation, one schema after the other
(ADR 0044). Ecto commits each migration by itself. When a migration fails
on the rows of one rescue, the migrations before it have run, and the
organisations before that one have changed. The old version may not run on
that database, and the operator restores a backup.

ADR 0073 asks for a migration that checks first and stops with a message.
Such a check stops the upgrade, and does not stop it before the other
migrations and the other organisations.

Four ways were read:

- **Checks that a migration declares**, run for each organisation before
  the first migration. They find only what the author thought of.
- **One transaction for the whole upgrade.** `Ecto.Migrator` runs each
  migration in a process and a transaction of its own, so this needs its
  private modules. One transaction over each organisation also holds each
  lock to its end, and a server with many organisations then passes the
  lock table of PostgreSQL.
- **A backup by itself before the migrations.** The image has the
  `pg_dump` 17 of Debian, which cannot dump PostgreSQL 18 (ADR 0050).
- **A rehearsal**: the whole upgrade in a transaction that is taken back,
  and the real run only after it passed.

## Decision

- **`bin/migrate` rehearses the upgrade before it changes anything**
  (`Rescord.Release.Rehearsal`). It runs each pending migration on one
  connection, in one transaction, and takes all of it back. When each one
  passed, it runs the migrations for real, as before.
- **The connection is the one of `Ecto.Adapters.SQL.Sandbox`**, on a
  second pool of `Rescord.Repo` that the rehearsal starts and stops. The
  sandbox is public API of `ecto_sql`: each process of the migrator gets
  the one connection, and the transaction never commits. No private
  module of Ecto is used.
- **The migrations of the database run first, then those of each
  organisation after a savepoint**, and the rehearsal goes back to the
  savepoint before the next organisation. So the locks of one organisation
  are free before the next one takes its own, and the report names each
  organisation with a fault, and not only the first.
- **The lock of Ecto is off in the rehearsal**: it is a transaction of the
  process that waits for the migration, on the connection that the
  migration needs. The real run keeps its lock.
- **A fault is the message and the hint of PostgreSQL, and not its
  detail.** The detail of a row that breaks a rule holds the values of the
  row, and the report goes to the log of the server (ADR 0077). The
  message of a data exception (class 22 of PostgreSQL), such as a text
  that is no number, holds the value too: for such an error the report
  has only the code. A message that a migration raises is the text of its
  author, who writes no value of a row into it.
- **When the rehearsal fails, nothing is changed.** `bin/migrate` prints
  the migration and the organisation of each fault, exits with 1, and the
  server does not start. The old version still runs on the database.
- **A new installation is not rehearsed**, and neither is a start with no
  pending migration, which costs one query for each organisation, as
  before.
- **`bin/migrate --rehearse`** rehearses and changes nothing, so an
  operator can try a new version before the day of the upgrade.
  **`bin/migrate --no-rehearsal`** migrates with no rehearsal, for a
  migration that cannot be rehearsed: the upgrade notes of its release say
  so. There is no setting for it: a switch in the environment would stay
  on. The NixOS module installs `rescord-migrate`.
- **No migration sets `@disable_ddl_transaction` or
  `@disable_migration_lock`**, and none builds an index `CONCURRENTLY`:
  such a statement cannot run in the transaction of the rehearsal, and
  Rescord is down during an upgrade, so it has no use for it.
  `Rescord.Release.MigrationRulesTest` holds the rule. This replaces rule
  6 of `docs/migrations.md` as ADR 0073 wrote it.

## What we tested

On PostgreSQL 18.7, with a database that has two organisations:

- With the newest migrations taken back (1 of the database, 3 of each
  organisation), `migrate` rehearsed, passed, and migrated both
  organisations.
- With a table of one of those migrations already in one organisation,
  the rehearsal named the migration and the organisation, `migrate`
  returned `:error`, and the versions and the tables of the database and
  of both organisations were the same before and after.
- A transaction with the DDL of one schema held 3 locks on relations, and
  none after `ROLLBACK TO SAVEPOINT`.
- `Rescord.Release.RehearsalTest` holds a unique index on rows with a
  double, a migration that checks first, a fault in each of two
  organisations, and a fault in the database.

## Consequences

- An upgrade runs each migration two times. A new table costs little. A
  data migration over a large table costs its time again, and the upgrade
  note of such a migration says that the first start takes longer.
- A migration that checks first (ADR 0073) now stops the upgrade before
  anything changes, and its message and hint are what the operator reads.
- The rehearsal is one transaction, and the real run is a transaction for
  each migration. A set of migrations that needs a commit between two of
  them, such as a new value of an enum type that a later migration uses,
  fails the rehearsal and would pass the real run. The test of an upgrade
  of each release (ADR 0051) rehearses that release, and
  `scripts/upgrade-test.sh` expects the line of the rehearsal, so such a
  set is found before a release.
- The real run is not atomic. A fault that the rehearsal cannot see, such
  as a server that stops in the middle, still leaves a database that only
  a backup puts back. The backup stays step 1 of an upgrade.
- A rehearsal beside a server that runs holds the locks of each table that
  it changes until it ends, so the pages of that organisation wait.
- With Docker Compose, a container whose rehearsal fails starts again, and
  rehearses again, until the operator puts the old version back. Each
  rehearsal changes nothing.
- The rehearsal starts a second pool of two connections for its time.
