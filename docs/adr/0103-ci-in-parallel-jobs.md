# ADR 0103: CI runs in parallel jobs from one build

Status: accepted (the maintainer asked on 28 November 2026 for a CI that is
comprehensive and runs side by side, and chose the parts of the tests and a
job of its own for the browser tests). The design is issue 32. It
changes the CI of ADR 0047 and keeps the rules of ADR 0078.

## Context

`ci.yml` ran one long job: the shell, the format, the advisories, the
compile and `mix test`, in a row on one runner. On 28 November 2026 the
tests took 16 minutes in the morning and 38 minutes by 08:11 UTC, with
1,787 tests, nearly all of them one at a time because each makes an
organisation.

The cache of mix seldom helped. `actions/cache` saves at the end of a job
that passed, and most runs of that day were cancelled by the next push or
failed. Its key had no fallback to another `mix.lock`, and the format check
compiled each dependency for dev while the compile did so again for test.
The flake check ran only for the files of its `paths`, and built Erlang,
Elixir and rebar3 from source each time (ADR 0053): 13 of its 18 minutes.

## Decision

- **One compile, saved at once.** The job "Compile, with no warning" runs
  `mix deps.get` and `MIX_ENV=test mix compile --warnings-as-errors`, and
  saves `platform/deps` and `platform/_build/test` with
  `actions/cache/save` right after the compile. A later cancel or failure
  keeps the build for the next run.
- **One key for each job.** `.github/actions/mix-cache` names the OS,
  `devenv.lock`, `mix.lock` and the commit. Its fallbacks are the newest
  build of the same lock, then of the same toolchain. Each job after the
  compile restores it and compiles nothing.
- **The checks of the code are a job of their own**, after the compile, in
  the test environment: the format, Credo once `platform/.credo.exs` is
  there (plain `mix credo`, issue 30), `mix hex.audit`,
  `mix deps.unlock --check-unused`, and `mix ash.codegen --check`, which
  fails when a resource needs a migration that nobody generated. Each step
  runs even when one before it failed, so one run shows each fault.
- **The tests run in parts.** `mix test --exclude playwright --partitions N`
  (N is 6) on N runners, each with its own PostgreSQL and its database
  `rescord_test<k>`. Mix deals all the sorted test files out in turn,
  before `--only` or `--exclude` picks the tests, so a part gets files, not
  a share of the time.
- **The browser tests run apart**, in M parts (M is 2), with
  `mix test --only playwright --partitions M`. `--only` finds a browser
  test in any file. A part with no browser test fails with "no test was
  executed", so M stays at or below the number of files of browser tests.
- **The workflows and the scripts are checked**: actionlint (with
  shellcheck of each `run:`), shellcheck of `scripts/`, nixfmt of the Nix
  files, and the self-test of `scripts/ci-catch-up.sh`.
- **The flake check runs in each run of CI.** `ci.yml` calls `nix.yml`,
  which keeps only its run from the Actions page. A change in `lib/` can
  break the start of a release, and the NixOS test is the one test that
  starts a release, migrates and runs each command of the server. A
  release calls CI and has no Nix job of its own.
- **The Nix store has a cache**: the Magic Nix Cache of Determinate
  Systems keeps each path that a run built in the cache of GitHub Actions,
  with FlakeHub and its diagnostics switched off.
- **The job "CI" gives one result** for the run: it fails when a job failed
  or was cancelled. The messages of the commits are skipped in a run with
  no push, which is no failure.
- **The matrices have `fail-fast: false`**, so each part reports.

## Consequences

- A run takes as long as its slowest path: the compile, then the slowest
  part of the tests; or the flake check.
- A run uses 10 runners at its peak, and the Free plan runs 20 jobs at
  once: a push run and a kept run (ADR 0078) fit side by side, and a third
  run waits for runners.
- The caches of mix and of Nix share the 10 GB of the repository, and GitHub
  evicts the least recently used entries first.
- N is 6 and M is 2 at first. The tests with no browser took about 35
  minutes in one job. The browser tests took 204 seconds on `main`, 105 of
  them in the file of `AccessibilityTest`, so a third part would end no
  sooner than two. The times of the parts in CI show when to change them. `mix test --slowest-modules`
  shows the slow files, outside CI: it turns on `--trace`, which runs every
  test one at a time.
- The Magic Nix Cache is an action of a company. Its free backend was
  deprecated in early 2025 and brought back in June 2025. If it goes again,
  the flake check only gets slower.
