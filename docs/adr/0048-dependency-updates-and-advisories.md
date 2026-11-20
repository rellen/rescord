# ADR 0048: Dependency updates and advisories

Status: accepted (the maintainer, 20 November 2026).

## Context

Nothing watched the dependencies. The actions fell behind by up to four
major versions, and a first `mix hex.audit` found two advisories: one in
`phoenix_live_view` 1.2.13, where a join without a URL skipped the
`on_mount` hooks of a `live_session`, which Rescord uses to find the member
and the role; and one in `assent` 0.2.13, in its Sign in with Apple code.

## Decision

- **CI runs `mix hex.audit`** on each push. Hex 2.6 reports a retired
  package and a package with a security advisory, and fails for either, so
  no new dependency does it.
- **An advisory that does not reach Rescord is acknowledged in `mix.exs`**,
  under `hex: [ignore_advisories: ...]`, with the reason and the condition
  to take it out. The audit still lists it as ignored.
- **`assent` is the first such advisory.** `ash_authentication` 4.15 locks
  it below 0.3, the fix is in 0.3.2, and Rescord has no OAuth strategy.
- **Dependabot** opens a weekly pull request for the Mix packages, with the
  minor and patch updates in one group, and one for the actions.
  `shoddy` and `shoddy_phoenix` stay pinned by hand (ADR 0005).
- **Elixir, Erlang/OTP and Debian change by hand**, in `devenv.lock` and in
  the `ARG` lines of `platform/Dockerfile`, which Dependabot cannot read.
  The image runs `apt-get upgrade` at each build, so a release has the
  security fixes of Debian.

## Consequences

- A new advisory fails CI until a dependency moves, or until somebody writes
  why it does not reach Rescord.
- A pull request of Dependabot that changes `platform/mix.lock` also needs
  the hash of `fetchMixDeps` in `nix/package.nix`, or the flake check fails.
- An image is not the same from one build to the next, because Debian
  changes. A release builds it once.
