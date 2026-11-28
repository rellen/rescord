#!/usr/bin/env bash
# Checks that the upgrade notes name each migration that an upgrade runs
# (ADR 0073, docs/migrations.md):
#
#   scripts/check-upgrade-notes.sh               the migrations since the last release
#   scripts/check-upgrade-notes.sh --since TAG   the migrations since the release TAG
#   scripts/check-upgrade-notes.sh --list        prints those migrations, and checks nothing
#   scripts/check-upgrade-notes.sh --self-test   shows that the check finds what it must
#
# A rescue that we do not know runs each migration at the first start of a
# new version, on its own data. So each migration of platform/priv/repo that
# is new since the last release has a line in CHANGELOG.md, under
# "### Upgrade notes" of a section above the one of that release, and the
# line holds the name of its file with no ".exs", such as
# `20261127182144_archive_task_subjects`. A migration of a release that is
# changed, renamed or removed needs such a line too: a rescue has run it, so
# the note says why it changed and what a rescue does.
#
# The last release is the newest tag `v...` before HEAD. The check reads the
# files of the working tree, the new ones too, so it runs before a commit.
# It needs the history and the tags: in a workflow, `fetch-depth: 0`.
# CI runs it for each push, and scripts/release.sh runs it before a release.
set -euo pipefail

stop() {
  echo "$1" >&2
  exit 2
}

directories=(platform/priv/repo/migrations platform/priv/repo/tenant_migrations)

# The text of each "### Upgrade notes" above the section of the version $1.
upgrade_notes() {
  awk -v stop="## [$1]" '
    index($0, stop) == 1 { exit }
    /^\[[^]]+\]: / { exit }
    /^## / { inside = 0; next }
    /^### / { inside = ($0 == "### Upgrade notes"); next }
    inside
  ' CHANGELOG.md
}

# The migrations that differ from the release $1, each as "status<TAB>path":
# A for a new one, and M or D for one of the release that changed or went.
# Without --no-renames, a renamed migration would hide the file that went.
differences() {
  git diff --no-renames --name-status "$1" -- "${directories[@]}"
  git ls-files --others --exclude-standard -- "${directories[@]}" | awk '{ print "A\t" $0 }'
}

check() {
  local base=$1 list=$2
  local version=${base#v}
  local notes status path name
  local new=() changed=() missing_new=() missing_changed=()

  [ -f CHANGELOG.md ] || stop "CHANGELOG.md is not at the root of the repository."
  notes=$(upgrade_notes "$version")

  while IFS=$'\t' read -r status path; do
    [ -n "$path" ] || continue
    case $path in *.exs) ;; *) continue ;; esac
    name=$(basename "$path" .exs)
    if [ "$status" = A ]; then
      new+=("$path")
      grep -qF -- "$name" <<<"$notes" || missing_new+=("$path")
    else
      changed+=("$path")
      grep -qF -- "$name" <<<"$notes" || missing_changed+=("$path")
    fi
  done < <(differences "$base" | sort -u -k2)

  if [ "$list" = true ]; then
    [ "${#new[@]}" -eq 0 ] || printf '%s\n' "${new[@]}"
    [ "${#changed[@]}" -eq 0 ] || printf "%s (in $base, and changed since)\\n" "${changed[@]}"
    return 0
  fi

  if [ "${#missing_changed[@]}" -gt 0 ]; then
    cat >&2 <<EOF
The release $base has these migrations, and they are changed or removed:

$(printf '  %s\n' "${missing_changed[@]}")

A rescue has run them, so a change to them does nothing for that rescue, and
a new installation then gets another database. Put each file back as $base
has it (git checkout $base -- FILE), and write a new migration. When a
released migration must change, name it under "### Upgrade notes" in
CHANGELOG.md and say why (docs/migrations.md).

EOF
  fi

  if [ "${#missing_new[@]}" -gt 0 ]; then
    cat >&2 <<EOF
These migrations are new since $base, and the upgrade notes do not name them:

$(printf '  %s\n' "${missing_new[@]}")

Add a line for each one to CHANGELOG.md, under "### Upgrade notes" of
"## [Unreleased]". The line holds the name of the file with no ".exs", says
where the migration runs and what it does to the data, and gives each step
by hand. docs/migrations.md has the form of the line.

EOF
  fi

  if [ "${#missing_new[@]}" -gt 0 ] || [ "${#missing_changed[@]}" -gt 0 ]; then
    return 1
  fi

  echo "New migrations since $base: ${#new[@]}. The upgrade notes name each one."
}

self_test() {
  local script work failed=0
  script=$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
  work=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT
  cd "$work"

  commit() {
    git add -A
    git -c user.name=test -c user.email=test@example.org -c commit.gpgsign=false \
      -c core.hooksPath=/dev/null commit --quiet -m "$1"
  }

  expect() {
    local name=$1 want=$2 got=0
    shift 2
    "$@" >/dev/null 2>&1 || got=$?
    if [ "$got" -eq "$want" ]; then
      echo "ok    $name"
    else
      echo "FAIL  $name: the check ended with $got, and not $want" >&2
      failed=1
    fi
  }

  changelog() {
    {
      printf '# Changelog\n\n## [Unreleased]\n\n'
      [ -z "$1" ] || printf '### Upgrade notes\n\n%s\n\n' "$1"
      printf '### Added\n\n- A thing. %s\n\n' "${2:-}"
      printf '## [0.1.0] - 2026-01-01\n\n### Upgrade notes\n\n- 20260101000000_first: the first tables.\n'
      printf -- '- 20260301000000_later is named in the wrong release.\n\n'
      printf '[Unreleased]: https://example.org/compare/v0.1.0...HEAD\n'
    } >CHANGELOG.md
  }

  git init --quiet --initial-branch=main .
  mkdir -p platform/priv/repo/migrations platform/priv/repo/tenant_migrations
  echo "first" >platform/priv/repo/migrations/20260101000000_first.exs
  changelog ""
  commit "chore(release): 0.1.0"
  git tag v0.1.0
  echo "no migration" >README.md
  commit "docs: a commit with no migration"

  expect "no new migration passes" 0 "$script"

  echo "second" >platform/priv/repo/tenant_migrations/20260201000000_second.exs
  expect "a new file with no commit and no note fails" 1 "$script"
  commit "feat: a migration with no note"
  expect "a new migration with no note fails" 1 "$script"

  changelog "" "The file 20260201000000_second is new."
  expect "a name outside the upgrade notes fails" 1 "$script"

  changelog "- \`20260201000000_second\`, in each organisation: adds a table."
  expect "a new migration with its note passes" 0 "$script"
  commit "docs: the note"
  expect "the same after the commit passes" 0 "$script"
  expect "the same with --since passes" 0 "$script" --since v0.1.0

  echo "later" >platform/priv/repo/migrations/20260301000000_later.exs
  expect "a name in the notes of an older release fails" 1 "$script"
  rm platform/priv/repo/migrations/20260301000000_later.exs

  echo "first, changed" >platform/priv/repo/migrations/20260101000000_first.exs
  expect "a changed migration of the release fails" 1 "$script"
  git checkout --quiet -- platform/priv/repo/migrations/20260101000000_first.exs

  git mv platform/priv/repo/migrations/20260101000000_first.exs \
    platform/priv/repo/migrations/20260101000001_first.exs
  changelog "- \`20260201000000_second\` and \`20260101000001_first\`: named."
  expect "a renamed migration of the release fails" 1 "$script"
  git reset --quiet --hard

  # The commit of a release: the notes are under the new version, and the
  # tag of that version is on HEAD or not made yet.
  awk '{ print } $0 == "## [Unreleased]" { print ""; print "## [0.2.0] - 2026-02-02" }' \
    CHANGELOG.md >CHANGELOG.md.new
  mv CHANGELOG.md.new CHANGELOG.md
  commit "chore(release): 0.2.0"
  expect "the commit of a release, with no tag yet, passes" 0 "$script"
  git tag v0.2.0
  expect "the commit of a release, with its tag, passes" 0 "$script"

  echo "after" >README.md
  commit "docs: a commit after the release"
  expect "after the release, nothing is new" 0 "$script"

  if [ "$failed" -ne 0 ]; then
    echo "The check of the upgrade notes does not do what it must." >&2
    exit 1
  fi
  echo "The check of the upgrade notes finds a migration with no note."
}

since=
list=false
while [ "$#" -gt 0 ]; do
  case $1 in
    --self-test)
      self_test
      exit 0
      ;;
    --list) list=true ;;
    --since)
      [ "$#" -ge 2 ] || stop "Give a tag after --since, such as v0.2.0."
      since=$2
      shift
      ;;
    *) stop "Give no argument, --since TAG, --list or --self-test." ;;
  esac
  shift
done

cd -- "$(git rev-parse --show-toplevel)"

if [ -z "$since" ]; then
  # HEAD^, so that the commit of a release that has its tag is compared with
  # the release before it.
  since=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 'HEAD^' 2>/dev/null) ||
    stop "No tag of a release is before HEAD in this clone. Fetch the history and the tags: git fetch --tags origin"
fi

git rev-parse --quiet --verify "$since^{commit}" >/dev/null ||
  stop "$since is not a tag of this clone. Fetch the tags: git fetch --tags origin"

check "$since" "$list"
