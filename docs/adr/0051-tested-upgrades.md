# ADR 0051: Tested upgrades

Status: accepted (the maintainer, 20 November 2026).

## Context

An upgrade runs the new migrations on the data of a rescue, at the first
start of the new version, in the database and in the schema of each
organisation. The old version may not run on a migrated database, so a
release that breaks an upgrade breaks each rescue, and only a backup goes
back.

## Decision

- **`scripts/upgrade-test.sh OLD NEW`** starts the database and the image
  `OLD` with the Compose file, and makes data with it: the first root user,
  an organisation with its schema, and a file. It then starts `NEW` on the
  same volumes, and checks that the root user, the organisation and the file
  are there, and that `bin/check` finds each migration of the database and
  of each organisation run.
- **The release runs it before it publishes.** The job `upgrade` builds the
  new image for amd64 from the cache of the build, and upgrades the image
  `latest` of the registry, which is the last release. The job `image`, which
  pushes, waits for it. A dry run runs it too.
- **The old version makes the data through its own functions**, so the
  script calls only `bin/bootstrap-root` and two functions of
  `Rescord.Accounts` that each release has had.

## Consequences

- A migration that fails on data, or a schema of an organisation that the
  new version does not migrate, stops the release before anything is
  published.
- The test upgrades from the last release only. A rescue that skips a
  release runs each migration between, in order, at its start, and no test
  takes that path.
- When the functions that the script calls change, the script changes in
  the same commit, and it must still work with the image of the last
  release.
