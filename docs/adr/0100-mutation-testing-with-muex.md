# ADR 0100: Mutation testing with muex, as a report that never fails a check

Status: accepted (the maintainer, 28 November 2026, asked to adopt the
mutation testing of the libraries shoddy and shoddy_phoenix in Rescord).
Issue 27 holds the design.

## Context

A line that a test runs is not a line that a test checks. Mutation testing
makes many copies of the code, each with one small change (a mutant), and
runs the tests on each copy. A mutant that no test kills shows a gap in the
tests.

`rellen/shoddy` and `rellen/shoddy_phoenix` use muex (Hex, MIT): an alias
`mix test.mutation` that runs muex with `--fail-at 0`, a job that writes the
JSON report, and `.github/scripts/muex_summary.exs`, which turns the report
into the summary of the job and a warning on the line of each mutant that
no test kills. They run it on each push.

Rescord cannot run it on each push. Its suite takes 25 to 40 minutes, muex
runs `mix test` again for each mutant, and `lib/` has about 470 files.

## Decision

- **muex 0.13 is a dependency of `dev` and `test`**, with `runtime: false`.
  The release holds none of it.
- **`mix test.mutation` runs muex in the environment `test`**, with
  `--fail-at 0`. Give it what to mutate, with `--files` or `--since`. The
  filter of muex stays on: it skips a file that it finds simple, such as a
  supervisor or a behaviour (`--no-filter` takes each one). It gives muex
  each test file outside `test/rescord_web/features/`: a browser test
  starts Chromium, which costs seconds for each mutant. For a mutant, muex
  runs the test files that name the module, and each of them when none
  does.
- **`--timeout 180000`** is the time with no output from a `mix test` of
  muex, not the time of the run. A mutant of a domain recompiles hundreds
  of files, and at 60 seconds four such mutants timed out.
- **A `mix test` of muex skips the set-up of the alias `test`.** muex runs
  each mutant in a copy of the project that has no `assets/`, so
  `assets.build` fails there, and `ash.setup` costs seconds for each
  mutant. `mix test.mutation` sets `RESCORD_MUTATION_RUN=1`, the runs of
  muex inherit it, and the alias `test` then has no set-up. Set up the test
  database and the assets once, before a run.
- **`--no-tce`.** The check of muex 0.13.1 for a mutant that compiles to the
  same code as the original compiles the file and compares the first module
  in the list that the compiler gives back. For a module with a `defimpl`
  or a module inside it, the first module is the inner one, which no
  mutant of the outer module changes. On `Rescord.Units.Quantity`, which
  has two `defimpl`, it called 36 of 44 mutants equivalent and ran no test
  for them. A resource of Ash has modules inside it too. With `--no-tce` the
  same mutants were killed or survived. muex still drops the mutants that
  its rules of the syntax prove equivalent.
- **`.github/workflows/mutation.yml` runs it, and no push starts it.** It
  runs by hand, with the files, the preset of muex and the time budget as
  inputs, and each Monday at 16:00 UTC on the lines that changed since the
  last tag of a release (`--since`), for 90 minutes. It runs in the devenv
  shell with PostgreSQL, as `ci.yml` does, and has a cache of its own.
- **A time budget, not a kill.** muex writes no report when the job is
  killed, so the run passes `--deadline-minutes`: after the budget, muex
  starts no new mutant and reports the ones that ran, marked partial. With
  a budget, muex takes the mutants of a file in an order that a fixed seed
  shuffles, and gives a free worker the file with the most mutants left.
  So a partial run is a sample, with more of the files that changed most.
- **A low score, a crash or a hang of muex never makes it fail**:
  `--fail-at 0`, continue-on-error on the step of muex, a limit of that
  step below the limit of the job, and a summary script that always exits
  0. A fault of the set-up, such as a compile error, still fails the job.
  The report goes outside `_build`, which the cache keeps, and the step
  removes it first: muex keeps a report that is there already. The script is the
  one of shoddy, with the paths of the annotations from the root of the
  repository (muex names them from `platform/`), the mutants in the order
  of the file and the line, and a line for a partial run. There is no
  comment on a pull request, because the work lands on `main`.
- **The workers of muex share the one test database, and start no
  server.** muex starts a worker for each core, up to the number of files
  with mutants, each in its own copy of the project, and runs the mutants
  of one file one at a time. Each test takes its own transaction of the
  SQL sandbox. The tests run a server on port 4002 for the browser tests,
  and two runs at one time cannot both have it: the second stopped with
  `:eaddrinuse`. So `config/test.exs` starts no server when
  `RESCORD_MUTATION_RUN` is set.

## Measured

In a cloud container with 4 cores, on 28 November 2026, on
`lib/rescord/units/quantity.ex` (44 mutants after the optimisation of
muex):

- One file gives one worker, so this run had one.
- A mutant of that module recompiles the 101 files that depend on it at
  compile time, which takes most of the 30 seconds of a killed mutant.
- A mutant that survives runs each chosen test file to its end: about 3
  minutes, with `journal_test.exs` and `inventory_test.exs` among them.
- 10 of the 44 mutants ran in a budget of 12 minutes: 5 killed, 3 survived,
  2 did not compile.

On the lines that changed since `v0.2.0` (6,270 mutants in 337 files), with
four workers: the first mutant of each took 2 to 3 minutes, the first run
of a copy compiling the whole project. All four were killed. With 60
seconds for `--timeout`, the same four had timed out.

So a run of 90 minutes covers about 75 mutants of one module like
`Quantity`, and more over many files, where four workers run at once. The
weekly run is a sample of the changes, not all of them.

## Consequences

- A score is no goal yet. A survivor is a lead for a test, not a fault.
- Fewer compile-time dependencies on a module make its mutants cheaper.
- A module that no test file names costs the most: each of its mutants
  that survives runs each test file outside the browser tests.
- A new directory of browser tests outside `test/rescord_web/features/`
  makes each mutant slower: keep them there.
- When muex fixes the check of equivalent code, take `--no-tce` out.
