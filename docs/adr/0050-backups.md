# ADR 0050: Backups

Status: accepted (the maintainer, 20 November 2026).

## Context

The guide told an operator how to back up, and nothing did it. Nobody had
put a backup back. A rescue that loses its server loses the history of each
resident.

## Decision

- **A backup is a dump and a copy.** A dump of the whole database in the
  custom format of `pg_dump`, with the schema of each organisation, named
  by the time in UTC; and a copy of each new file of the store. A file that
  the copy has is not copied again, because Rescord never changes a file.
  A dump older than `RESCORD_BACKUP_KEEP_DAYS` days, 14 by default, is
  deleted.
- **A restore puts the newest dump**, or one that the operator names, into
  an empty database with `pg_restore`, and copies the files back.
- **Each package runs it by itself:**
  - the release has `bin/backup` and `bin/restore`, for the tarball with a
    systemd timer and for the NixOS module;
  - the NixOS module runs `bin/backup` each day into `/var/lib/rescord-backup`,
    with the `pg_dump` of its PostgreSQL, and installs `rescord-restore`;
  - the Compose file has a service `backup` in the image of PostgreSQL 18,
    which backs up into `./backups` at its start and each 24 hours. The
    image of Rescord has the `pg_dump` 17 of Debian, which cannot dump
    PostgreSQL 18, so the service has a copy of the script.
- **A bucket of S3 is not copied.** Its provider keeps versions of it.

## Consequences

- The backups are on the server. An operator copies them to another place
  too, with the secrets, which the backup does not hold: without
  `RESCORD_KEY_SECRET`, the keys of the transfers do not open.
- The NixOS test makes a root user and a file, backs them up, empties the
  database and the files, restores, and finds both. The same steps passed
  with the Compose file.
- The two scripts must do the same thing. A change to one is a change to
  the other.
