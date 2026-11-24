# Changelog

Each release of Rescord has a section here. The release workflow puts the
section of a version in the notes of its GitHub release (ADR 0047).

## Unreleased

- Security: Phoenix LiveView 1.2.14. In 1.2.13, a join of a page without a
  URL skipped the `on_mount` hooks of its `live_session`, which find the
  member and the role on the pages of an organisation.
- `bin/check` says whether a server is ready: the database, the
  migrations, the store, the SMTP server, and a test email.
- Backups each day in each way of installing, and `bin/restore` to put one
  back.
- Each release now tests an upgrade from the last release, with its data,
  before it publishes anything.
- CI fails on a dependency with a security advisory, and Dependabot
  proposes updates each week.
- The dependencies are at their newest versions of 24 November 2026:
  Ash 3.38, Phoenix LiveView 1.2.15, Postgrex 0.23, PostgreSQL 18.7, and
  Debian 13 of 23 November 2026 in the image.

## 0.1.0 - 2026-11-20

The first release, for a rescue that runs Rescord on a server of its own.

### What Rescord does

- The sign-in by a link in an email, with no password. A link works one
  time, the answer to a request does not say whether an address has an
  account, and each address and each client has a limit.
- A root user, made by a command when Rescord is first deployed. A root user
  makes organisations and invites their administrators, and an administrator
  invites the members.
- Each organisation keeps its data in a schema of its own, and defines its
  roles, with the powers of each.
- The residents, with their history: names, breeds, colours, temperaments,
  desex status, families and groups.
- The housing as a tree of locations, and the placement of each resident or
  group.
- The journal of each resident, with medical entries, and photos and PDFs
  attached to an entry.
- The tasks and the routines that make them, and the inventory: items, lots,
  suppliers, stock movements, units and reorder levels.
- The timeline of a resident.
- Transfers of a resident between partner refuges, on one server or between
  two servers by a signed and encrypted file.

### How to run it

- A Docker image for amd64 and arm64, with a Compose file of PostgreSQL 18,
  Rescord and Caddy.
- A Nix flake with a package and a NixOS module.
- A tarball for amd64 and arm64, with a systemd unit.
- The mail goes through any SMTP server, and the files go to a directory or
  to a service that is compatible with S3, with the bucket in the path or
  in the host.
- Rescord counts the limits of the sign-in by the address of the client
  behind a trusted reverse proxy.
- `docs/self-hosting.md` lists each setting, and says how to back up and
  upgrade.
