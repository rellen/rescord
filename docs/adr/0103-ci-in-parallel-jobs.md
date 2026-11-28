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
  on J runners, each with its own PostgreSQL. Mix deals all the sorted
  test files out in turn, before `--only` or `--exclude` picks the tests,
  so a part gets files, not a share of the time, and parts differ a lot.
  So each runner has N / J small parts and runs them in 4 slots
  (`scripts/test-in-parts.sh`; J is 8 and N is 96): a slot takes the next
  part that no slot has taken when its part ends, so the slots stay busy
  to the end with no file of test times. Slot k has the database
  `rescord_test<k>`, the port 4002 + k and a directory of files of its own
  (RESCORD_TEST_SLOT). The floor is the slowest test file: a few files
  take about 2 minutes each, and a part holds one file or more.
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
- **The Nix store has a cache on Cachix**, the public cache `rescord` of
  the maintainer (28 November 2026). A run of CI on `main` (a push, or a
  run from the Actions page) writes to it with the secret
  `CACHIX_AUTH_TOKEN`; every other run only reads it, and a pull request
  from a fork has no token at all. A filter keeps out the sources and the
  run of the NixOS test, which runs again each time. The package of
  Rescord is kept all the same, since it is in the closure of the test
  machine. The first run that filled the cache took 17.6 minutes; the next,
  on a commit that changed only tests, 1.5 (it fetched the package and ran
  the NixOS test, 67 seconds). A commit that changes the package builds it
  again, about 4 minutes with the test. The
  Magic Nix Cache of Determinate Systems was in the first build. It keeps
  each path of the store as an entry of the cache of GitHub Actions, and
  the first run hit the rate limit of that cache about 400 times. A job of
  mix in the next run then got 429 for its own restore and compiled
  everything again.
- **The job "CI" gives one result** for the run: it fails when a job failed
  or was cancelled. The messages of the commits are skipped in a run with
  no push, which is no failure.
- **The matrices have `fail-fast: false`**, so each part reports.

## Consequences

- A run takes as long as its slowest path: the compile, then the slowest
  part of the tests; or the flake check.
- A run uses up to 12 runners at once (the checks, 8 jobs of tests, 2 of
  browser tests and the flake check), and the Free plan runs 20 jobs at
  once: when a push run and a kept run (ADR 0078) overlap, some jobs of the
  second wait a few minutes for runners. J was 6 (24 parts) at first; the
  maintainer chose 8 on 28 November 2026, rather than a file of test
  times to balance the parts.
- The caches of mix and of Nix share the 10 GB of the repository, and GitHub
  evicts the least recently used entries first.
- N was 6 at first, one part on each runner. The tests with no browser
  took about 35 minutes in one job, and the six parts 4 to 9 minutes each
  (28 November 2026). Most tests run one at a time (a test that makes an
  organisation is `async: false`, ADR 0022), so one `mix test` kept one of
  the four cores busy. On a machine with 4 cores and 16 GB, like a runner,
  a part took 22 to 24 per cent longer beside 2 or 3 others than alone, so
  4 parts at once do about 3.2 times the work of one. The script sets up
  the databases and builds the assets once, and the alias `test` skips its
  set-up when RESCORD_TEST_SET_UP is 1: two builds of the assets at once
  would write the same files. M is 2. The browser tests took 204 seconds on `main`, 105 of
  them in the file of `AccessibilityTest`, so a third part would end no
  sooner than two. The times of the parts in CI show when to change them.
  `mix test --slowest-modules` shows the slow files, outside CI: it turns
  on `--trace`, which runs every test one at a time.
- With no cache, the flake check built Erlang, Elixir and rebar3 in each
  run, about 18 minutes, the longest path of a run. With the cache, a run
  builds them only after a change of `flake.lock` or of `nix/`, and the
  longest path is the tests again.
- Each job after "Compile" gives the files the time of the commit after it
  restored the build of that commit, so mix compiles nothing. A checkout
  gives each file the time of now, newer than the build, and mix then
  compiled the 500 files of the app again in each job. Mix still finds a
  changed file by its digest.
