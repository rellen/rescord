# ADR 0073: Each migration is written for a rescue that we do not know, and has its upgrade note

Status: accepted (the maintainer asked for it on 28 November 2026). It adds
to the releases of ADR 0060 and to the tested upgrades of ADR 0051.

## Context

Rescord is open source, and others can host it (ADR 0044). A start of a
new version runs each migration that has not run, in the database and in
the schema of each organisation, on data that we have never seen. The old
version may not run on the result, so the way back is a backup.

ADR 0060 gave each release a section "Upgrade notes", and ADR 0051 made
the release test an upgrade from the last release. Two things were missing:

- No rule said how to write a migration for the data of another rescue:
  what to do with a row that breaks a new rule, how to change rows, and
  what a step by hand looks like.
- Nothing held the notes to the migrations. The notes of 0.2.0 said "a
  migration of the database, and a migration of each organisation". That
  release had no migration of the database, and two of each organisation.

Several threads add migrations to `main` on the same day, and a commit on
`main` cannot be changed.

## Decision

- **`docs/migrations.md` holds the rules of a migration**, and `AGENTS.md`
  the short form. In brief: a migration of a release never changes; a
  migration runs by itself and calls no code of Rescord; a new rule on a
  table states what happens to an old row that breaks it; a data migration
  is a file of its own, in SQL, and says what it does to the history; a
  step by hand is the last choice, and is a breaking change (ADR 0060).
- **Each migration has a line in the upgrade notes**, written in the
  commit that adds the migration, under "Upgrade notes" of "Unreleased".
  The line holds the name of the file, where the migration runs (the
  database, or each organisation), what it does for an operator, what it
  does to the rows that are there, and what an operator can notice. The
  lines are a list under the entry "**Migrations.**".
- **A step by hand is in the upgrade notes in full**, under "**Before the
  upgrade.**" or "**After the upgrade.**": why, a query that finds the
  rows, how to put each right, how to know that the step is done, and
  what happens without it. An operator needs no other document. A cleaning
  of data that only a person of the rescue can decide goes to the members,
  in the pages, where that is possible, and not to the operator in SQL.
- **`scripts/check-upgrade-notes.sh` holds the notes to the migrations.**
  It compares `platform/priv/repo` with the last release. It fails for a
  new migration whose name is not in the upgrade notes above the section
  of that release, and for a migration of that release that is changed,
  renamed or removed and not named there. It runs in three places: a job
  of `ci.yml` for each push, so a release runs it too (ADR 0060);
  `scripts/release.sh`, before it makes the commit of a release; and by
  hand before a commit. `--self-test` shows that it finds each case.
- **The name of the file is the key**, because the log of a start that
  fails gives an operator the number at the start of that name, and
  because a check can find it.
- **The upgrade notes of 0.2.0 are put right** in `CHANGELOG.md`, in this
  form. The notes of the GitHub release of 0.2.0 stay as they were
  published, until the maintainer changes them.
- The upgrade notes stay in `CHANGELOG.md`. A file for each release was
  not taken: the number of a release is not known before its commits are
  (ADR 0060), and an operator would have two places to read.

## Consequences

- A thread that adds a migration and no line fails the job "The upgrade
  notes of the migrations" on `main`, and the next thread sees it. The
  job does not stop the push: `main` takes no pull request. A release
  stops.
- The check finds a name, and no more. Whether the line says the truth
  about the rows is for the person who writes it, and for the person who
  reads the notes before a release (`docs/migrations.md`, "Before a
  release").
- The changelog names files of the source. That is more than an operator
  reads on a good day, and what an operator needs on a bad one.
- The release tests an upgrade from the last release only, with little
  data (ADR 0051). A migration that changes or checks rows adds rows of
  that kind to `scripts/upgrade-test.sh`. A test of an upgrade with the
  data of a large rescue is not built. A check of each migration before
  the first one runs came after this ADR: the rehearsal of ADR 0081,
  which also replaces what this ADR said about `@disable_ddl_transaction`.
- The check needs the history and the tags of the repository. A clone
  with no tag stops it with a message, and does not pass it.
