# Migrations and the upgrade of a rescue

This guide is for a person, or an agent, who changes the database of
Rescord. It says how to write a migration that is safe for a rescue, and
what each release tells an operator about its migrations. ADR 0073 holds
the decision, `AGENTS.md` holds the short rules, and
`docs/self-hosting.md`, "Upgrade", is what the operator reads.

## Who runs a migration

Rescord is open source, and a rescue runs it on a server of its own
(ADR 0044). So a migration is not run by us:

- **A person whom we do not know runs it**, with no developer near. The
  operator takes a new version and starts it, and the start runs each
  migration that has not run (`Rescord.Release.migrate/0`).
- **It runs on data that we have never seen.** A rescue has rows from each
  older version, rows that a fault of an older version left, and more rows
  than a database for development.
- **It runs one time for the database, and one time for each
  organisation.** `platform/priv/repo/migrations` is for the tables that
  the organisations share, and `platform/priv/repo/tenant_migrations` is
  for the schema of each organisation (ADR 0011). A server with 40
  organisations runs a tenant migration 40 times, one schema after the
  other, and Rescord answers no request until the last one ends.
- **It can run a long time after we wrote it.** An upgrade from each older
  release is supported (ADR 0060). A rescue that jumps from 0.2.0 to 0.6.0
  runs the migrations of four releases in order, with the code of 0.6.0.
- **The way back is a backup.** The old version may not run on a database
  that a migration changed. When a migration of an upgrade fails, the
  migrations before it, and the organisations before this one, have
  changed already.

The operator has one source for all of this: the section "Upgrade notes"
of each release in `CHANGELOG.md`, which the release workflow puts in the
notes of the GitHub release.

## The rules of a migration

1. **A migration of a release never changes.** Do not edit it, do not give
   it another name, and do not remove it. A rescue has run it, so the
   change does nothing there, and a new installation then gets a database
   that no rescue has. Put a fault right with a new migration.
   `scripts/check-upgrade-notes.sh` refuses a changed migration of the
   last release. In the rare case that one must change, such as a
   migration that a new PostgreSQL refuses, the upgrade notes name it and
   say why, and a new migration does the same for each rescue that ran
   the old one. A migration on `main` that no release has can still
   change, but each database for development that ran it must then be made
   again (`mix ash.reset`). Prefer a new migration there too.
2. **Read each migration that the generator writes**, in both
   directories. `mix ash.codegen` writes what the resources need, and does
   not know the rows of a rescue. Look for:
   - a column or a table that it removes: see "A migration that removes";
   - an attribute with a new name: the generator writes a new column and
     the removal of the old one, which loses each value. Change that to
     `rename`;
   - a new rule on a column that has rows: see "A rule that old rows can
     break";
   - a tenant migration: run
     `mix run --no-start -e "Rescord.TenantMigrations.repair!()"` after the
     generator (ADR 0025).
3. **A migration runs by itself.** It asks nothing, reads no setting, and
   needs no network. When an upgrade needs a person, that is a step by
   hand: see below.
4. **A migration calls no code of Rescord.** It uses the functions of
   `Ecto.Migration` and SQL through `execute/1`. It does not call a
   resource, a function of a domain, or `Rescord.Repo`: that code changes
   in later releases, and the migration must do the same thing for a
   rescue that runs it a year from now. Write a fixed value, such as the
   key of a power, into the migration.
5. **A migration works on no row and on many rows.** A new installation
   and each new organisation run each migration on empty tables, before
   the code makes the first rows. A rescue runs it on its rows.
6. **A migration stays in its transaction.** Ecto runs each migration in a
   transaction, so a migration that fails leaves its own change undone.
   Set `@disable_ddl_transaction true` only for a statement that PostgreSQL
   refuses inside a transaction, in a migration that holds nothing else,
   and say so in the upgrade note.
7. **A migration has a `down`** that undoes it where that is possible. A
   developer uses it; an operator goes back with a backup, and never with
   `down`. When `down` cannot give back what `up` removed or changed, say
   so in the `@moduledoc`.
8. **A new need of the server is an upgrade note**, and can be a breaking
   change (ADR 0060): a newer PostgreSQL, an extension of PostgreSQL, or a
   right that the role of the database may not have.
9. **A patch release has no migration** when that is possible (ADR 0060).

### A rule that old rows can break

A migration that adds `null: false`, a unique index, a check, a foreign
key or an exclusion to a table with rows fails when one row of one rescue
breaks the rule. Then that rescue does not start. Before you write such a
migration, decide what happens to a row that breaks the rule. In this
order of preference:

1. **The migration puts the rows right by a rule that loses nothing**,
   and the upgrade note states the rule. For example: a new required
   column gets a default, or the value of another column. This is a data
   migration: see the next section.
2. **The upgrade keeps the rows, and Rescord asks a member.** When only a
   person of the rescue can decide, such as which of two records is the
   right one, do not make the operator decide in SQL. Keep the old rows
   out of the rule: put the rule in the resource and not in the database,
   or add a check or a foreign key with `NOT VALID`, which holds for each
   new row and each change, and not for the rows that are there. Then
   show the rows to a member who can put them right, as a row of what
   needs attention (ADR 0065). The upgrade note says what the members
   will see.
3. **A step by hand, before the upgrade.** This is the last choice, and it
   is a breaking change: mark the commit with `!`. The upgrade note gives
   the step in full (see "A step by hand"), and a migration checks the
   rows first and stops with a message that an operator can act on.

A migration that only fails with the error of PostgreSQL, such as
`could not create unique index`, is a fault of the release.

### A migration that removes

A migration that removes a column or a table, makes a type narrower, or
deletes rows cannot be undone without a backup.

- The upgrade note says what goes, in the words of a person of the rescue:
  "the notes of a supplier", and not only "the column `notes`".
- When a rescue can still want the values, keep them: move them where the
  new version shows them, in a data migration of the same release, and
  remove the old place in a later release.
- Do not remove in a patch release.

### A migration that takes long

A migration that writes each row of a large table again, or that builds
an index on one, takes time in each organisation, and Rescord is down
until the last one ends. The tables that grow are the journal, the
versions of each record, the stock movements, the tasks and the photos.
Say in the upgrade note that the first start takes longer, and for which
tables.

## A data migration

A data migration changes rows: it fills a new column, moves values, puts
old rows right, or gives a role a new power.

- **It is a file of its own**, apart from the migration that changes the
  tables, with a name that says what it does:
  `give_administrators_the_export`, `fill_the_unit_of_each_item`. A change
  of the tables that needs the rows first comes in a later file. Write
  the file by hand; the name of the module follows the name of the file.
- **It is SQL in `execute/1`.** In a tenant migration, name each table
  with `prefix()`:

  ```elixir
  defmodule Rescord.Repo.TenantMigrations.GiveAdministratorsTheExport do
    @moduledoc """
    Gives the role with the key `administrator` the power `export`
    (ADR 0054). `down` takes the power from each role, also from a role
    that an administrator gave it to.
    """

    use Ecto.Migration

    def up do
      execute("""
      UPDATE "#{prefix()}"."roles"
      SET powers = array_append(powers, 'export')
      WHERE key = 'administrator' AND NOT ('export' = ANY(powers))
      """)
    end

    def down do
      execute("""
      UPDATE "#{prefix()}"."roles"
      SET powers = array_remove(powers, 'export')
      """)
    end
  end
  ```

- **It changes only the rows that need the change.** The `WHERE` leaves
  out a row that is right already, so the statement can run a second time
  and change nothing.
- **It does not guess.** When no rule gives the right value for a row,
  leave the row, and use the second or the third choice of "A rule that
  old rows can break".
- **It knows the history.** The table of a temporal resource has one row
  for each version of a record, with its period in `valid_at` (ADR 0012).
  A statement with no condition on the period changes each past version
  too, and a read as of a past date then gives another answer than
  before. SQL also writes nothing in the paper trail. Decide which
  versions the statement changes, and say in the `@moduledoc` and in the
  upgrade note what the migration does to the history.
- **It says what it changes.** The upgrade note names the rows and the
  rule, so that an operator knows which data is different after the
  upgrade.

## The upgrade note of a migration

**Each migration has a line in `CHANGELOG.md`**, in the same commit, under
`### Upgrade notes` of `## [Unreleased]`. `scripts/check-upgrade-notes.sh`
fails for a migration with no line. The notes of a release with a
migration have these parts, in this order:

```markdown
### Upgrade notes

- **Before the upgrade.** Each step by hand that comes before the new
  version, numbered, with what to type. Leave this part out when there
  is none.
- **Migrations.** The first start of this version runs each of these by
  itself. Make a backup first, as `docs/self-hosting.md` says.
  - `20261127182144_archive_task_subjects`, in each organisation: adds a
    column to the subjects of the tasks. It changes no row.
  - `20261125120000_give_administrators_the_export`, in each
    organisation: gives the role with the key `administrator` the power
    `export`. No other row changes.
- **After the upgrade.** Each step by hand that comes after the first
  start, and what the members will see. Leave this part out when there
  is none.
```

The line of a migration holds:

- **the name of its file**, with no `.exs`, in backticks. The log of a
  start that fails gives the number at the start of that name
  (`== Running 20261127182144 ...`), so an operator finds the line;
- **where it runs**: "in the database", for `priv/repo/migrations`, or
  "in each organisation", for `priv/repo/tenant_migrations`;
- **what it does, for a person who runs a server**: the part of Rescord
  that it is for, and not a list of columns;
- **what it does to the rows that are there**: "It changes no row", or
  which rows change and by which rule, or what it removes;
- **what an operator can notice**: a first start that takes longer, a
  step by hand, a new need of the server.

A thread that adds a migration adds its line to the list under
"**Migrations.**", and makes that part when it is not there. Each other
entry of "Upgrade notes", such as a new setting, stays an entry of its
own.

### A step by hand

A step by hand is in the upgrade notes in full. An operator must not need
the source, an ADR or this guide. Give:

1. **Why**, in one sentence.
2. **How to find the rows**: a query that the operator copies, and how to
   run it for each organisation. The schema of an organisation is `org_`
   and its id:

   ```sql
   SELECT short_name, 'org_' || id AS schema FROM organisations;

   -- For each schema of the list:
   SELECT name, count(*) FROM "org_<id>".clinics
   GROUP BY name HAVING count(*) > 1;
   ```

   (`clinics` is an example, and no table of Rescord.)
3. **How to put each row right**, with the pages of the old version where
   that is possible, and with SQL only where no page can. Say what a
   person must decide.
4. **How to know that the step is done**: the query finds no row.
5. **What happens without the step**: the migration stops, with which
   message, and the operator restores the backup of step 1 of the guide.
6. **Which release to stop at**, when the step needs the pages of a
   release that is between the two versions of a rescue that jumps.

The migration that needs the step checks first, in a file of its own that
comes before the change, and stops with a message that names the step:

```elixir
defmodule Rescord.Repo.TenantMigrations.CheckThatEachClinicHasOneName do
  @moduledoc """
  Stops the upgrade while two clinics of the organisation have one name.
  The next migration makes the name unique. The upgrade notes of the
  release say how an operator puts the names right first.
  """

  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE
      doubles bigint;
    BEGIN
      SELECT count(*) INTO doubles
      FROM (
        SELECT name FROM "#{prefix()}"."clinics"
        GROUP BY name HAVING count(*) > 1
      ) AS same;

      IF doubles > 0 THEN
        RAISE EXCEPTION 'Rescord cannot upgrade: % names of clinics are used more than one time in the schema %.', doubles, '#{prefix()}'
          USING HINT = 'Restore the backup, start the old version, and do the step "Before the upgrade" of the upgrade notes of this release.';
      END IF;
    END
    $$;
    """)
  end

  def down, do: :ok
end
```

## Try a migration before the commit

- **`mix test`** makes the test database from each migration, and makes
  an organisation, so it runs each migration on empty tables. It runs none
  on the rows of a rescue.
- **Run it on rows.** Use a database for development that has records in
  two organisations or more, and that the commit before your change
  made. Run `mix ash_postgres.migrate` for a migration of the database,
  and `mix ash_postgres.migrate --tenants` for a tenant migration. Then
  run the `down` and the `up` again: `mix ash_postgres.rollback -n 1` or
  `mix ash_postgres.rollback --tenants -n 1`, and the same `migrate`.
  Read the rows that the migration changed.
- **`scripts/upgrade-test.sh OLD NEW`** is the test of an upgrade that the
  release runs (ADR 0051): the image of the last release makes data, and
  the new image takes it over. Its data is small. When your migration
  changes or checks rows, add rows of that kind to the script, with the
  functions of the last release, or with SQL for a row that only an older
  version could leave, and add an `expect` for them after the upgrade.
  The workflow Release with `dry_run` runs it without a release.
- **`scripts/check-upgrade-notes.sh`** says whether each new migration
  has its line. `--list` prints the migrations that are new since the
  last release.

## Before a release

`scripts/release.sh` stops when a migration has no upgrade note. Before
you run it, read the section "Upgrade notes" of "Unreleased" as an
operator who has never seen the code:

- Each line of "**Migrations.**" is still true. A later commit can change
  what a migration means for a rescue.
- The steps by hand are complete, in the order in which an operator does
  them, and each query runs.
- A release with a step by hand has a commit with `!`, so its number says
  so (ADR 0060).
- The release test of an upgrade passes: run Release with `dry_run` when a
  migration changes or checks rows.
