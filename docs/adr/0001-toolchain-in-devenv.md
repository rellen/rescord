# ADR 0001: The toolchain comes from devenv

Status: accepted

## Context

The project needs Elixir 1.20.5, Ash and Phoenix at their latest versions,
and PostgreSQL 18, on NixOS and macOS. The binaries that the esbuild and
tailwind Hex packages download do not run on NixOS.

## Decision

- `devenv.nix` takes the BEAM toolchain from one package set,
  `pkgs.beam.packages.erlang_29`: Elixir 1.20 (1.20.5 at the locked nixpkgs)
  on Erlang/OTP 29, the newest OTP that Elixir 1.20 supports, and elixir-ls
  built against that Elixir.
- `devenv.yaml` tracks `nixpkgs-unstable`, which had Elixir 1.20.5;
  `devenv.lock` pins the commit.
- `services.postgres` runs PostgreSQL 18 on `127.0.0.1`, and its
  `initialScript` creates the `postgres`/`postgres` superuser that Phoenix's
  generated config uses. `config/dev.exs` and `config/test.exs` read `PGHOST`
  and `PGPORT`, which devenv sets.
- esbuild comes from nixpkgs. devenv sets `MIX_ESBUILD_PATH`, and
  `config/config.exs` gives it to the esbuild Hex package as `path`, with
  `version` set to the nixpkgs version. Without the variable, the package
  downloads esbuild as usual.
- `MIX_HOME` and `HEX_HOME` are inside `.devenv/state`, and the shell installs
  Hex and rebar3 when they are missing.

## Consequences

- When nixpkgs bumps esbuild, change `version` in `config/config.exs`, or the
  Hex package logs a version warning.
- devenv's PostgreSQL refuses to run as root, so a cloud session that runs as
  root needs another way to get a database. That is an open question.
