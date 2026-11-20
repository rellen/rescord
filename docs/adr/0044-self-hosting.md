# ADR 0044: Self-hosting

Status: accepted (the maintainer, 20 November 2026).

## Context

A rescue, or a group of rescues, will run Rescord on a server of its own.
It may not use Tigris for the files, or Postmark for the mail. Before this
record, a release had no task to migrate, a mailer that sent nothing in
production, a default store of one service, and a web server that only
bound to IPv6.

## Decision

- **One release, three packages**, each from `mix release`:
  - a Docker image (`platform/Dockerfile`), with a Compose file of
    PostgreSQL 18, Rescord and Caddy (`deploy/compose`);
  - a Nix package and a NixOS module (`flake.nix`, `nix/`);
  - a tarball for x86-64 and ARM64 with a systemd unit
    (`scripts/release-tarball.sh`, `deploy/systemd`), built on Debian
    bookworm for glibc 2.36.

  We do not make a single binary, a Helm chart, or packages of a
  distribution: they cost more than the rescues that would use them.
- **`Rescord.Release`** migrates the database and the schema of each
  organisation, and makes the first root user, with no Mix. The release
  ships `bin/server`, `bin/migrate` and `bin/bootstrap-root`. Each package
  runs `bin/migrate` before each start, so an upgrade migrates by itself.
- **The mail goes through any SMTP server**, with `gen_smtp`: STARTTLS by
  default, TLS from the start, or none for a relay on the same machine.
  With TLS, the client checks the certificate and the name of the server.
- **The files go to a directory by default** (`RESCORD_STORAGE=disk`), or
  to any service that is compatible with S3. The endpoint of S3 has no
  default.
- **Each setting comes from the environment**, and a missing required one
  stops the start with its name. `docs/self-hosting.md` lists them, and
  `Rescord.ProductionConfigTest` reads `config/runtime.exs` as a release
  does.
- **The web server listens on `RESCORD_LISTEN_ADDRESS`**: `0.0.0.0` by
  default, because a Docker network has no IPv6 unless its operator turns
  it on, and `127.0.0.1` in the NixOS module and the systemd unit, behind
  a reverse proxy on the same machine.
- **HTTPS comes from a reverse proxy**: Caddy in the Compose file, nginx in
  the NixOS module, and one that the operator chooses for the tarball.
  Rescord sends a request without HTTPS to HTTPS, except `/health` and a
  request to `localhost`.
- **No distributed Erlang**: each package sets `RELEASE_DISTRIBUTION=none`,
  so nothing but the web server listens.
- **PostgreSQL 18 or later**, as `Rescord.Repo.min_pg_version/0` says. The
  NixOS module asserts it.

## Consequences

- An operator backs up three things: the database, the files, and the
  secrets, of which `RESCORD_KEY_SECRET` opens the keys of the transfers
  between servers (ADR 0043).
- A migration runs at a start, so the old version may not run on a
  migrated database. An operator goes back with a backup.
- The dependencies of the Nix package have a hash in `nix/package.nix`,
  which changes with `platform/mix.lock`. `nix build` prints the new one.
- The tarball does not run on a system older than Debian 12 or Ubuntu
  24.04. Such a system uses the Docker image. The tarball links the
  OpenSSL of the system where it is built: a release built on Debian
  trixie needs OpenSSL 3.4, and on Ubuntu 24.04, which has OpenSSL 3.0, it
  stops at the start because `:crypto` cannot load (measured on 20
  November 2026). So the script builds on bookworm, and the image, which
  carries its own system, builds on trixie.
- `GET /health` answers without a session, and says only whether the
  database answers.
