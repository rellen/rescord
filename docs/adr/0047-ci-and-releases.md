# ADR 0047: CI and releases

Status: accepted (the maintainer, 20 November 2026).

## Context

Nothing ran the tests on a push, and nothing published the packages of ADR
0044, so a rescue had to build Rescord itself. The browser tests need the
Playwright of nixpkgs, and the toolchain is pinned by `devenv.lock`.

## Decision

- **`ci.yml` runs inside the devenv shell**, on each push to `main` and each
  pull request: the format, the locked dependencies, a compile of the test
  support with no warning, and `mix test` with PostgreSQL 18 from devenv.
  CI and a machine for development then have one toolchain.
- **Under `CI=true`, a missing Playwright driver stops the tests**, so a run
  cannot pass with the browser tests left out.
- **`nix.yml` runs `nix flake check`** with KVM, when a file that the
  package reads for its dependencies changes, and for each release.
- **`release.yml` releases the version of `platform/mix.exs`**, which must
  have a section in `CHANGELOG.md`: for a pushed tag `vX.Y.Z` that names
  it, or from the Actions page on `main`, which then makes the tag. A
  session of Claude Code can push a branch and not a tag, so it starts a
  release from the Actions page. After the flake
  check, it publishes the image to `ghcr.io` for amd64 and arm64, and a
  GitHub release with the two tarballs, `SHA256SUMS`, and the section of the
  changelog.
- **arm64 builds under QEMU** on a runner of amd64. A runner of arm64 is not
  in each plan of GitHub, and a job for a runner that the account does not
  have waits with no error.
- **A release is a tag on `main`**, after the version and the changelog
  change in one commit. A run from the Actions page refuses a tag that
  exists.

## Consequences

- An image or a release of a private repository is private: a rescue needs
  access to the repository, or the maintainer makes the package public.
- The builds under QEMU are slow, so a release takes most of an hour. Native
  runners of arm64 can replace QEMU when the plan has them.
- The CI of a push costs the minutes of one runner of Linux. The flake
  check runs only for the files of its paths.
