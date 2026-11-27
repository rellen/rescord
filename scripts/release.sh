#!/usr/bin/env bash
# Makes the commit of a release (ADR 0060):
#
#   scripts/release.sh           the size of the release from the commits
#   scripts/release.sh minor     or major, or patch: overrules the commits
#   scripts/release.sh 0.2.0     this version
#   scripts/release.sh --print   says the new version, and changes nothing
#
# It reads the Conventional Commits since the tag of the version of
# platform/mix.exs: a breaking change gives a major, or a minor before
# 1.0.0; a `feat` gives a minor; all else gives a patch. It writes the new
# version in platform/mix.exs, gives the section "Unreleased" of
# CHANGELOG.md the version and the date, opens a new empty one, updates the
# links at the end of the file, and commits `chore(release): X.Y.Z`.
#
# The date is today, or RELEASE_DATE, such as 2026-11-28. The script does not
# push, and it makes no tag. Push the commit to main, and run the
# workflow Release on main from the Actions page: it makes the tag after
# each check passed. Or push the tag vX.Y.Z, which starts the same workflow.
#
# It stops when the tree is not clean, when HEAD is not the newest commit of
# main on origin, or when "Unreleased" has no entry.
set -euo pipefail

stop() {
  echo "$1" >&2
  exit 1
}

print=false
want=
for argument in "$@"; do
  case $argument in
    --print) print=true ;;
    major | minor | patch) want=$argument ;;
    [0-9]*.[0-9]*.[0-9]*) want=$argument ;;
    *) stop "Give major, minor, patch, a version such as 0.2.0, or --print." ;;
  esac
done

cd -- "$(dirname -- "$0")/.."

# The version of platform/mix.exs, and its tag.
old=$(sed -nE 's/^ +version: "([^"]+)",$/\1/p' platform/mix.exs | head -n 1)
[[ $old =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  stop "platform/mix.exs has no line such as: version: \"0.1.0\","

git fetch --quiet origin main "refs/tags/v$old:refs/tags/v$old" ||
  stop "Cannot fetch main and the tag v$old from origin: is the version $old of platform/mix.exs released?"

if [ "$print" = false ]; then
  [ -z "$(git status --porcelain)" ] || stop "The tree is not clean: commit or remove each change."
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] ||
    stop "HEAD is not the newest commit of main on origin."
fi

range="v$old..HEAD"
[ -n "$(git rev-list "$range")" ] || stop "No commit since v$old."

# The size that the commits give.
size="patch"
if git log --no-merges --format=%s "$range" | grep -qE '^feat(\([^)]*\))?!?: '; then
  size=minor
fi
if git log --no-merges --format=%s "$range" | grep -qE '^[a-z]+(\([^)]*\))?!: ' ||
  git log --no-merges --format=%b "$range" | grep -qE '^BREAKING[ -]CHANGE: '; then
  size=major
fi

IFS=. read -r major minor patch <<<"$old"
# Before 1.0.0, a breaking change raises the minor.
if [ "$size" = major ] && [ "$major" -eq 0 ]; then
  size=minor
fi

case ${want:-$size} in
  major) new="$((major + 1)).0.0" ;;
  minor) new="$major.$((minor + 1)).0" ;;
  patch) new="$major.$minor.$((patch + 1))" ;;
  *)
    new=$want
    [[ $new =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || stop "$new is not a version such as 0.2.0."
    newest=$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -n 1)
    { [ "$new" != "$old" ] && [ "$newest" = "$new" ]; } || stop "$new is not after $old."
    ;;
esac

if [ "$print" = true ]; then
  echo "$new"
  exit 0
fi

echo "The commits since v$old give a $size release. The new version is $new."

# The changelog: "Unreleased" must have an entry, and its links must be there.
entries=$(awk '
  /^## \[/ { inside = ($0 == "## [Unreleased]"); next }
  /^\[[^]]+\]: / { inside = 0 }
  inside && /^- / { count++ }
  END { print count + 0 }
' CHANGELOG.md)
[ "$entries" -gt 0 ] || stop "The section \"## [Unreleased]\" of CHANGELOG.md has no entry."

link_end="/compare/v$old...HEAD"
grep -qF "$link_end" CHANGELOG.md ||
  stop "CHANGELOG.md has no link \"[Unreleased]: ...$link_end\"."

today=${RELEASE_DATE:-$(date +%F)}
awk -v old="$old" -v new="$new" -v today="$today" -v link_end="$link_end" '
  $0 == "## [Unreleased]" {
    print
    print ""
    print "## [" new "] - " today
    next
  }
  index($0, "[Unreleased]: ") == 1 && index($0, link_end) > 0 {
    url = substr($0, length("[Unreleased]: ") + 1)
    base = substr(url, 1, length(url) - length(link_end))
    print "[Unreleased]: " base "/compare/v" new "...HEAD"
    print "[" new "]: " base "/compare/v" old "...v" new
    next
  }
  { print }
' CHANGELOG.md >CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md

# The version, in its one home.
awk -v old="$old" -v new="$new" '
  !done && $0 ~ /^ +version: "[^"]+",$/ {
    sub("\"" old "\"", "\"" new "\"")
    done = 1
  }
  { print }
' platform/mix.exs >platform/mix.exs.new
mv platform/mix.exs.new platform/mix.exs
grep -qE "^ +version: \"$new\",$" platform/mix.exs || stop "platform/mix.exs did not take the version $new."

git add CHANGELOG.md platform/mix.exs
git commit --quiet -m "chore(release): $new"

cat <<EOF
Made the commit "chore(release): $new". Read it with: git show
Then push it to main, and run the workflow Release on main from the Actions
page, which makes the tag v$new. Or push the tag yourself:
  git tag -a v$new -m "Rescord $new" && git push origin main v$new
EOF
