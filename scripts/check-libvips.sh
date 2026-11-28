#!/usr/bin/env bash
# Says whether Hex has a newer vix or image than platform/mix.lock
# (issue 37, ADR 0113):
#
#   scripts/check-libvips.sh   exits 1 when one of them is newer, 0 when not
#
# libvips and its decoders (libjpeg, libpng, libwebp, giflib) read each
# photo that a person sends, inside the BEAM, as the NIF of vix. The check of
# advisories in CI covers the Hex packages only, and a fix of libvips reaches
# the Docker image and the tarball only with a new version of vix, which
# brings its own build of libvips. So a newer vix is read as a fix of
# security that waits, until its notes say otherwise. image is the library
# over vix that Rescord calls.
#
# The weekly workflow `libvips.yml` runs it. It needs bash, curl and jq, and
# no Elixir. With GITHUB_STEP_SUMMARY set, it writes a table there too.
set -euo pipefail

lock=platform/mix.lock
[ -f "$lock" ] || {
  echo "Run it from the root of the repository: $lock is not here." >&2
  exit 2
}

newer=0
rows=()

for package in vix image; do
  # A line of mix.lock: "vix": {:hex, :vix, "0.44.0", ...
  locked=$(grep -oE "^  \"$package\": \{:hex, :$package, \"[^\"]+\"" "$lock" | grep -oE '"[^"]+"$' | tr -d '"') || locked=""
  [ -n "$locked" ] || {
    echo "mix.lock has no version of $package." >&2
    exit 2
  }

  latest=$(curl -fsS --retry 3 "https://hex.pm/api/packages/$package" | jq -r '.latest_stable_version') || latest=""
  [ -n "$latest" ] && [ "$latest" != "null" ] || {
    echo "Hex gave no stable version of $package." >&2
    exit 2
  }

  highest=$(printf '%s\n%s\n' "$locked" "$latest" | sort -V | tail -n 1)

  if [ "$latest" != "$locked" ] && [ "$highest" = "$latest" ]; then
    newer=1
    state="newer on Hex"
    echo "$package: mix.lock has $locked, Hex has $latest. Read its changelog, and update it."
  else
    state="up to date"
    echo "$package: $locked, the newest on Hex."
  fi

  rows+=("| $package | $locked | $latest | $state |")
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## libvips: vix and image"
    echo
    echo "| Package | mix.lock | Hex | |"
    echo "| --- | --- | --- | --- |"
    printf '%s\n' "${rows[@]}"
    echo
    if [ "$newer" = 1 ]; then
      echo "A newer version can bring a fix of libvips or of a decoder. Read its changelog, update it with \`mix deps.update\`, update the hash of the dependencies of the Nix package, and name a new libvips under \"Security\" in CHANGELOG.md."
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

exit "$newer"
