# ADR 0049: Check the server

Status: accepted (the maintainer, 20 November 2026).

## Context

A wrong setting showed itself late. A wrong SMTP password, for example,
showed only when the first sign-in link did not arrive, and the server log
was the only place that said why.

## Decision

- **`bin/check`** (`Rescord.Release.check/1`, `Rescord.Release.Check`)
  prints one line for each check, and exits with 1 when one fails:
  - the database answers and is PostgreSQL 18 or later;
  - the migrations that have not run, as a note and not a fault;
  - the store takes a file, gives the same bytes back, and deletes it;
  - the SMTP server takes the connection, the TLS and the user, with
    `gen_smtp_client:open/1`, which sends no mail;
  - with an address, a short email goes to it.
- **The check starts only what it needs**: the repository with a small
  pool, Req and gen_smtp. It does not start the application, whose jobs
  would run, and which would stop at a wrong setting before a check could
  name it.
- **No line shows a password or a key**, and each fault is in words: a
  refused user, a server with no STARTTLS, no connection.
- The NixOS module installs `rescord-check`, which runs it with the user
  and the environment of the service.

## Consequences

- An operator runs it before going live, and after a change of a setting.
- The tests talk to the example SMTP server of `gen_smtp`, so the check of
  a user and a password is tested against a real SMTP session. The NixOS
  test runs `rescord-check` against Postfix, and the test email arrives.
- A setting that `config/runtime.exs` refuses still stops `bin/check`
  before the first line, with the name of the setting.
