# ADR 0052: Install from main, and the MIT licence

Status: accepted (the maintainer, 21 November 2026).

## Context

The maintainer will not release Rescord, or change its version, for some
time. The one release, 0.1.0, is older than `bin/check`, the backups and a
security fix of Phoenix LiveView, and the guide told an operator to install
it. The repository had no licence, so nobody could run or change the code.

## Decision

- **Rescord is under the MIT licence** (`LICENSE`). The typeface in
  `platform/priv/static/fonts/` keeps its own licence.
- **The guide installs from the branch `main`**: the Compose file uses the
  image `rescord:local`, which `docker build` makes from the repository; the
  NixOS example follows the flake on `main`, which `flake.lock` pins to a
  commit; and the tarball is built with `scripts/release-tarball.sh`.
- **The version stays 0.1.0.** The release workflow, its dry run and the
  test of an upgrade stay, for the day of the next release (ADR 0047,
  ADR 0051), and `CHANGELOG.md` collects the changes under "Unreleased".

## Consequences

- An operator builds Rescord, which takes some minutes, and upgrades with
  `git pull` and a new build, or `nix flake update`.
- A commit on `main` reaches a rescue at its next upgrade, so CI on `main`
  is the gate that a release would be.
