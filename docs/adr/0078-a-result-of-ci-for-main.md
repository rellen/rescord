# ADR 0078: Main gets a result of CI, even when pushes cancel each other

Status: accepted (the maintainer chose it on 28 November 2026: keep the
cancel, and run later when the newest commit of `main` has had no run for
an hour). It adds a workflow to the CI of ADR 0047.

## Context

Work lands on `main` with no pull request, and several sessions push on
the same day. A run of `ci.yml` takes 11 to 17 minutes. Its concurrency
cancels the run of a push when the next push comes, so that the runners
work on the newest commit only.

On 28 November 2026 thirteen pushes came from 05:21 to 06:12 UTC, none
more than 11 minutes after the one before. Each of their runs was
cancelled, and after more than an hour nobody knew whether `main` passed.
Each session had run its own tests before its push, on its own change and
not on the changes of the others together.

Two simple answers do not fit. With no cancel, each push runs for its
whole time, and a queue of runs works on commits that are no longer the
newest. A run at a fixed time, with no run for a push, gives a quiet day
its result up to an hour late.

## Decision

- **A push to `main` still cancels the run of the push before it.** On a
  quiet day the push itself gives the result, in a quarter of an hour.
- **A run of `ci.yml` that starts on `main` as `workflow_dispatch` is
  kept.** The concurrency of `ci.yml` gives it a group of its own, with no
  cancel, so no push cancels it. A second kept run waits for the first to
  end. A run that a session starts on its own branch is as before: the
  newer run cancels the older one.
- **`ci-catch-up.yml` runs three times an hour** and starts a kept run
  when `main` has waited an hour for a result. The rule is in
  `scripts/ci-catch-up.sh`:
  - A run has a result when it ended as a success, a failure, a timeout
    or a failure to start. A cancelled run has none.
  - When the newest commit of `main` has a result, or a kept run is on
    its way, nothing starts.
  - Otherwise the script takes the oldest run that started after the
    last result. When that run started an hour ago or more, the script
    starts `ci.yml` on `main`. Before that hour, it waits: the run of
    the newest push may still end.
- **The hour counts from the first push with no result**, and not from the
  newest commit. When pushes come without a pause, the newest commit is
  always a few minutes old, and a rule about its age would never start a
  run.
- **A run of the newest push that still runs does not stop the kept
  run.** The script cannot know whether the next push will cancel it. So
  after a busy hour, the newest commit can have two runs, one of the push
  and one that is kept. That costs the minutes of one runner.
- **The workflow starts `ci.yml` with the token of its own run**, which
  has the permission to write the actions. An event `workflow_dispatch`
  from that token does start a workflow, which a push from it does not.
  No secret is needed.
- **`scripts/ci-catch-up.sh --self-test` shows that the rule decides each
  case**, and the workflow runs it first.
- **From the Actions page**, the workflow takes the minutes to wait, where
  0 starts a kept run now, and a dry run that says what would happen and
  starts nothing. To get a result for `main` by hand, a person can also
  start `CI` itself on `main` there.

## Consequences

- When pushes do not stop, `main` gets a result about every 80 minutes:
  the hour, and up to 20 minutes until the next run of the schedule. The
  result is for the commit that was the newest when the kept run started.
- GitHub starts a scheduled run late when it is busy, and can leave one
  out. Three runs an hour make one lost run cost 20 minutes.
- GitHub stops the schedule of a public repository after 60 days with no
  commit. `main` then has no pushes to cancel, so nothing is lost. A fork
  has no schedule until its owner turns its workflows on.
- A kept run is a run of the event `workflow_dispatch`, so the job that
  checks the messages of the commits of a push does not run in it. That
  job takes seconds, and ends in the run of the push before a cancel in
  nearly each case.
- In a release from the Actions page on `main`, the checks of CI are kept
  too, in a group of the release: a second release waits for the checks of
  the first, where it cancelled them before.
- A failure of a kept run names no push. The runs that were cancelled
  since the last success show which commits to look at.
