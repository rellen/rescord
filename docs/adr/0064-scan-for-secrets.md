# ADR 0064: A scan keeps secrets and the details of a deployment out of the repository

Status: accepted (the maintainer chose it on 28 November 2026, with the
sweep of the policies of ADR 0063, from the review of Chironium). It adds a
job to the CI of ADR 0047.

## Context

This repository is public. The rule of the maintainer is that nothing
confidential goes into it: no secret, token or password, no personal
detail, and nothing that belongs to one deployment, such as the host name
or the configuration of the server of a refuge. Such things belong in the
environment of a server, or in the private repository of the deployment.

The rule was a rule for people and for agents, and nothing checked it. A
commit on `main` cannot be changed (ADR 0060), and work lands on `main` with
no pull request. A secret that reaches `main` is public from that moment.

## Decision

- **Gitleaks scans each commit**, with `scripts/check-secrets.sh` and the
  rules of `.gitleaks.toml`. Gitleaks is in nixpkgs, so the devenv shell
  has it, and CI takes it from the nixpkgs of `flake.lock`. No new action
  of GitHub is needed.
- **In CI, a job of its own scans the whole history at each push.** The
  history is small, and the scan takes a second. One rule thus covers the
  first scan of the history, each later push, and a push that rewrites a
  branch.
- **Before a commit, the devenv shell installs the script as the hook
  `pre-commit`**, which scans what the commit holds. CI comes after the
  push, which is too late for a secret on `main`. A session with no devenv
  shell runs the script before it pushes (`AGENTS.md`).
- **Three rules of our own, beside those of Gitleaks.** They find what
  belongs to one person or to one deployment, and they name no deployment:
  an email address that is not one of the example domains; the host name
  of an app on a hosting service, such as `<app>.fly.dev`; and a file
  `fly.toml`.
- **The names of a deployment come from outside the repository.** A rule
  that names the server of a refuge would put that name in a public file.
  The script reads a list of private terms, one on each line: the file that
  `RESCORD_PRIVATE_TERMS` names, or `.private-terms` at the root, which Git
  ignores. In CI the list is the secret `PRIVATE_TERMS` of the repository,
  and the report hides what it found, because the log of CI is public.
  With no list, the scan runs with the rules of the repository alone.
- **Each exception is an allowlist in `.gitleaks.toml`, with its reason.**
  The script turns off the comment `gitleaks:allow`, so a file cannot
  switch off a finding about itself. The one allowlist at the start is for
  the fixed secrets of development and of the tests, which the generator of
  Phoenix wrote into `config/dev.exs` and `config/test.exs`: three named
  settings in those two files, and not the files.
- **`scripts/check-secrets.sh --self-test` shows that each rule finds its
  sample**, and that the examples pass. CI runs it first. A scan that finds
  nothing because a rule is broken looks the same as a clean repository.

## The first scan

The first scan read the 100 commits of the history on 28 November 2026.
The rules of Gitleaks found six values, all of them the fixed secrets of
development and of the tests that the allowlist now names. A server reads
each secret from its environment (`config/runtime.exs`), and
`Rescord.ProductionConfigTest` holds that. The rules of Rescord, and the
names of the deployment of the maintainer as private terms, found nothing.

## Consequences

- A push with a secret fails in CI, and a commit with one fails in the
  devenv shell before it exists.
- A finding in CI on `main` is already public. The scan then says so: the
  secret must be changed where it is used, and a later commit that removes
  it does not make it a secret again.
- The rules for a host name know five hosting services. A deployment on
  another service is found only by its private terms.
- A real address in a file, such as a contact for security reports, needs
  an allowlist with its reason.
- The maintainer keeps the secret `PRIVATE_TERMS` up to date when a
  deployment gets a new name.
- A pull request from a fork has no secret, and is scanned with the rules
  of the repository alone.
