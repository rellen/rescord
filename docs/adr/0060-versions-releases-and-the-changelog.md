# ADR 0060: Versions, releases and the changelog

Status: accepted (the maintainer, 28 November 2026).

## Context

Rescord has one release, 0.1.0, and ADR 0052 stopped the releases: a rescue
installs from `main`, and so does the private repository that deploys an
instance. Then nobody can say which Rescord a server runs, or which changes
an upgrade brings. The maintainer wants versions with Git tags, and a
changelog, and does not want Rescord on hex.pm.

The release workflow of ADR 0047 and the test of an upgrade of ADR 0051
stay. This ADR adds the rules that they did not have: what a version number
means, how the changelog and the commit messages are written, and who pins
what.

Two models were read. Cinder writes its changelog by hand, with a section
"Unreleased", and uses no tool. The libraries of Ash, such as
ash_authentication, write Conventional Commits and let git_ops generate the
changelog from the subjects of the commits. Their readers are developers.
The readers of the changelog of Rescord run a server, and need sentences
written for them.

## Decision

### What a version means

- **Rescord follows Semantic Versioning 2.0.0.** Its public interface is
  what an operator or a partner server relies on:
  - the settings: the environment variables and the options of the NixOS
    module;
  - the commands of `bin/`, and the format of a backup;
  - the layout of each way to install: the image, the Compose file, the
    tarball and the systemd units;
  - the requirements, such as the oldest PostgreSQL;
  - the upgrade: a start runs the migrations that have not run;
  - the formats that others read: the transfer file, a transfer between
    servers, and the CSV export.
- **Major**: an upgrade needs more than a backup, the new version and a
  start, or the last major can no longer exchange a transfer with this one.
  Examples: a setting is removed or becomes required, the oldest PostgreSQL
  goes up, a migration needs a step by hand.
- **Minor**: a feature, a setting with a default, a migration that runs by
  itself, an addition to a format.
- **Patch**: a fix, or an update for security or of a dependency. It has no
  migration when that is possible.
- **Before 1.0.0, a breaking change raises the minor**, and the changelog
  says so first. 1.0.0 comes when a rescue that the maintainer does not run
  depends on Rescord.
- **Only the newest release gets fixes.** An upgrade from each older
  release is supported. The release tests the upgrade from the one before
  (ADR 0051).

### The changelog

- **`CHANGELOG.md` is written by hand, in the format of Keep a Changelog
  1.1.0.** A section `## [Unreleased]` is at the top. A release has the
  heading `## [X.Y.Z] - YYYY-MM-DD`, and the links that compare two tags
  are at the end of the file.
- **A release has these sections, in this order, and leaves out an empty
  one**: "Upgrade notes", for what an operator must do or know, and then
  Added, Changed, Deprecated, Removed, Fixed and Security. "Upgrade notes"
  is not a section of Keep a Changelog. Rescord adds it because its reader
  upgrades a server.
- **A commit that an operator can notice adds its entry** under
  "Unreleased", in the same commit. An entry is one or more full sentences
  for an operator. It is not the subject of the commit.
- The sections of 0.1.0 and the entries under "Unreleased" move to this
  format one time.

### The commit messages

- **Each commit on `main` follows Conventional Commits 1.0.0**:
  `type(scope)!: subject`. The types are `feat`, `fix`, `perf`, `refactor`,
  `docs`, `test`, `build`, `ci`, `chore` and `revert`. The scope is
  optional, and `fix(security)` marks a security fix. A `!` or a footer
  `BREAKING CHANGE:` marks a breaking change.
- **The commits give the size of a release.** A breaking change gives a
  major, or a minor before 1.0.0. A `feat` gives a minor. All else gives a
  patch.
- **A commit that does not follow the rule cannot be changed on `main`**,
  so three things keep the rule: `AGENTS.md` states it, the devenv shell
  installs a hook `commit-msg` of Git that refuses a bad message, and a job
  of `ci.yml` fails on one. `scripts/check-commit-message.sh` is the check
  of both. A merge commit is exempt. Dependabot writes its commits with the
  prefix `chore(deps)`.
- The rule starts with the commit after the release 0.2.0. The older
  commits stay as they are.

### How a release is made

- **`platform/mix.exs` is the one home of the version.** `nix/package.nix`
  reads it from that file, and keeps no copy.
- **`scripts/release.sh`**, in bash, with no argument: reads the commits
  since the last tag and finds the new version, writes it in `mix.exs`,
  gives the section "Unreleased" its version and its date, opens a new
  empty one, updates the links, and makes the commit
  `chore(release): X.Y.Z`. It stops when the tree is not clean, when HEAD is
  not the newest commit of `main`, or when "Unreleased" has no entry.
  `major`, `minor`, `patch` or a version as an argument overrules what the
  commits give.
- **The workflow Release then runs on `main` from the Actions page**, as
  ADR 0047 says, and makes the tag `vX.Y.Z` at the commit that it built,
  after each check passed. A pushed tag still starts the same workflow.
- **Release also runs the checks of `ci.yml`**, as it runs `nix.yml`. Until
  now it checked the flake and the upgrade, and not the tests.
- **Rescord says its version**: `bin/check` prints it, and a page of the
  root user shows it.
- **The first release under these rules is 0.2.0**, with what is under
  "Unreleased" now. The maintainer says when.
- **From 0.2.0, the guide installs a release again**: the image by its tag,
  the flake by its tag, and the tarball of the GitHub release. This ends
  the part "install from `main`" of ADR 0052. The MIT licence of that ADR
  stays.

### The repository that deploys an instance

- A repository that deploys Rescord pins a tag:
  `inputs.rescord.url = "github:rellen/rescord/vX.Y.Z"`. An upgrade changes
  that line, runs `nix flake update rescord`, and deploys.

## Consequences

- An operator reads the upgrade notes of each release between the two
  versions, and knows from the number whether an upgrade needs a step by
  hand.
- A fix reaches an instance only with a release, so a security fix needs a
  patch release on the same day.
- No dependency is added. git_ops, mix_version, expublish, versioce and
  git-cliff were read and not taken: the first and the last generate the
  changelog from the commits, and a script of some lines does the rest.
- The changelog and the commit messages say some things two times. That is
  the price of entries written for an operator.
- Between two releases, a build from `main` carries the version of the last
  release. A version such as `0.3.0-dev` on `main` was not taken, because
  the size of the next release is not known before its commits are.
- The tag that the workflow makes is a lightweight tag. For an annotated
  or a signed tag, the maintainer pushes the tag, and the workflow runs for
  it.
