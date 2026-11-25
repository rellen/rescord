# ADR 0053: Erlang/OTP ahead of nixpkgs

Status: accepted (the maintainer, 25 November 2026).

## Context

Erlang/OTP 29.1.3, of 24 November 2026, fixes nine CVEs. Three are in the
`binary_to_term` of `erts`: a buffer overrun, an abort and a crash on input
that is encoded wrong. The others are in `inets`, `xmerl`, `snmp`, the JIT
of ARM64 and macOS. Rescord decodes no term from outside, but the runtime
is under each part of it. The images of `hexpm/elixir` had 29.1.3 the day
after, and the branch `nixpkgs-unstable` still had 29.1.2.

## Decision

- **The image and the tarball take 29.1.3** from the `OTP_VERSION` of
  `platform/Dockerfile`.
- **The Nix package takes 29.1.3 too.** `flake.nix` overrides the `erlang`
  of `beam.packages.erlang_29` with the source of the tag `OTP-29.1.3`,
  fetched with `fetchgit`, and Elixir builds on it. The override does
  nothing when the `erlang_29` of nixpkgs is 29.1.3 or later.
- **devenv and CI stay on the Erlang of nixpkgs.** An Erlang that is not in
  the binary cache would build from its source in each run of CI.

## Consequences

- Until nixpkgs has 29.1.3, the tests run on 29.1.2, and what a rescue runs
  is 29.1.3. The upgrade test and the NixOS test run the builds of 29.1.3.
- The flake check builds Erlang from its source, which makes it slower,
  until nixpkgs has 29.1.3. Then the override does nothing, and it can go.
- The hash of the source is that of a checkout with git. The archive of
  GitHub has another hash, because the repository of Erlang leaves some
  files out of its archives.
