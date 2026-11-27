#!/usr/bin/env bash
# Checks that the message of a commit follows Conventional Commits 1.0.0
# (ADR 0060): `type(scope)!: subject`, with one of the types below.
#
#   scripts/check-commit-message.sh FILE          the message in FILE, as the
#                                                 hook commit-msg of Git gives it
#   scripts/check-commit-message.sh --range A..B  each commit of the range
#
# A merge commit is exempt. With --range, the commits of the release 0.2.0
# and before it are exempt too: the rule starts after that release.
set -euo pipefail

types='feat|fix|perf|refactor|docs|test|build|ci|chore|revert'
pattern="^($types)(\([a-z0-9][a-z0-9 ,./_-]*\))?!?: [^ ].*$"
first_release=v0.2.0

usage() {
  echo "Give the file of a message, or --range A..B." >&2
  exit 2
}

# Whether the subject follows the rule. A merge commit is exempt.
follows() {
  [[ $1 =~ ^Merge\  ]] || [[ $1 =~ $pattern ]]
}

explain() {
  cat >&2 <<EOF
The message of a commit follows Conventional Commits (ADR 0060):

  type(scope)!: subject

The type is one of:

  ${types//|/, }

The scope and the "!" of a breaking change are optional. For example:

  feat(photos): show the date of a photo under it
  fix(security): refuse a transfer file with a path outside its directory
EOF
}

[ "$#" -ge 1 ] || usage

if [ "$1" = --range ]; then
  [ "$#" -eq 2 ] || usage
  range=$2

  # A push of a new branch has no commit before it, and Git gives zeros.
  if [[ $range =~ ^0+\.\. ]]; then
    echo "No commit before this push: nothing to check."
    exit 0
  fi

  if ! git rev-parse --quiet --verify "refs/tags/$first_release" >/dev/null; then
    echo "The tag $first_release does not exist yet: the rule starts after it."
    exit 0
  fi

  bad=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    commit=${line%% *}
    subject=${line#* }
    if ! follows "$subject"; then
      echo "::error::$commit: $subject" >&2
      bad=1
    fi
  done < <(git log --no-merges --format='%h %s' "$range" --not "refs/tags/$first_release")

  if [ "$bad" -ne 0 ]; then
    explain
    exit 1
  fi
  echo "Each commit of $range follows Conventional Commits."
else
  [ "$#" -eq 1 ] && [ -f "$1" ] || usage
  # The first line that is not a comment of Git is the subject.
  subject=$(grep -v '^#' "$1" | head -n 1 || true)
  if ! follows "$subject"; then
    echo "Not a Conventional Commit: $subject" >&2
    explain
    exit 1
  fi
fi
