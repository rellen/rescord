#!/usr/bin/env bash
# Scans for what this repository must not hold (ADR 0064): a secret, an
# address of a real person, and what belongs to one deployment. It runs
# Gitleaks with the rules of `.gitleaks.toml`.
#
#   scripts/check-secrets.sh              each commit of the history of HEAD
#   scripts/check-secrets.sh --staged     what the next commit holds, as the
#                                         hook pre-commit of Git runs it
#   scripts/check-secrets.sh --self-test  shows that each rule of Rescord
#                                         finds what it is for
#
# The names of a deployment are not in this repository, which is public. A
# list of private terms holds them: a file with one term on each line, as
# plain text, where a line that starts with `#` is a comment. The script
# reads the file that RESCORD_PRIVATE_TERMS names, or else `.private-terms`
# at the root of the repository, which Git ignores. A term is found in any
# case of its letters. With no list, the scan runs without one, and says so.
#
# The devenv shell has Gitleaks. Without it:
#
#   nix shell --inputs-from . nixpkgs#gitleaks -c scripts/check-secrets.sh
set -euo pipefail

usage() {
  echo "Give no argument, --staged or --self-test." >&2
  exit 2
}

# As the hook pre-commit, the script is a link in the hooks of Git.
mode=history
if [ "$(basename "$0")" = pre-commit ]; then
  mode=staged
elif [ "$#" -eq 1 ] && [ "$1" = --staged ]; then
  mode=staged
elif [ "$#" -eq 1 ] && [ "$1" = --self-test ]; then
  mode=self-test
elif [ "$#" -ne 0 ]; then
  usage
fi

if ! command -v gitleaks >/dev/null; then
  cat >&2 <<'EOF'
Gitleaks is not on the PATH. The devenv shell has it. Without the shell:

  nix shell --inputs-from . nixpkgs#gitleaks -c scripts/check-secrets.sh
EOF
  exit 2
fi

root=$(git rev-parse --show-toplevel)
rules=$root/.gitleaks.toml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Writes the rules of a scan to $work/rules.toml: the rules of the
# repository, and one rule more for the private terms of the file $1, when
# it has a term.
write_rules() {
  local terms=$1 pattern=''

  if [ -n "$terms" ] && [ -r "$terms" ]; then
    # Each term as plain text: a backslash before each character that means
    # something in a regular expression.
    pattern=$(
      grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$terms" |
        sed -e 's/[[:space:]]*$//' -e 's/[][\\.^$*+?(){}|]/\\&/g' |
        paste -s -d '|' -
    ) || true
  fi

  if [ -z "$pattern" ]; then
    cp "$rules" "$work/rules.toml"
    return 1
  fi

  if [[ $pattern == *"'''"* ]]; then
    echo "A private term cannot hold three single quotes in a row." >&2
    exit 2
  fi

  # The rule goes after the rules of the repository, in one file. A file
  # that extends the other would lose its allowlists.
  cp "$rules" "$work/rules.toml"
  cat >>"$work/rules.toml" <<EOF

[[rules]]
id = "rescord-private-term"
description = "A term of the list of private terms: a name of one deployment, which belongs in its private repository"
regex = '''(?i)(?:$pattern)'''
EOF
}

# Runs Gitleaks with the rules of the scan. A comment in a file cannot
# switch a finding off. In CI the report does not show what it found,
# because a log of CI is public and a private term is not.
scan() {
  local redact=()
  [ -z "${CI:-}" ] || redact=(--redact)

  gitleaks "$@" --config "$work/rules.toml" --ignore-gitleaks-allow --no-banner \
    --verbose "${redact[@]}"
}

explain() {
  cat >&2 <<'EOF'

The scan found what this repository must not hold (ADR 0064).

  - A secret, a token or a password belongs in the environment of a server,
    and never in a commit. A secret that reached a commit is no secret any
    more, even after a later commit removes it: change it where it is used.
  - What belongs to one deployment, such as its host name or its
    configuration, belongs in the private repository of that deployment.
  - An address in an example is one of example.org.
  - A finding that is no secret takes an allowlist in .gitleaks.toml, with
    its reason.
EOF
}

self_test() {
  local samples=$work/samples report=$work/report.json failed=0
  mkdir -p "$samples/deploy"

  # Each sample is put together here, so that this file holds no finding of
  # its own. The first of the reversed lines is a password, and the second
  # is the address of a database with its password.
  local at='@' dot='.'
  echo "write to jane${at}wattle-creek${dot}org${dot}au" >"$samples/email.txt"
  echo "open https://wattle-creek${dot}fly${dot}dev/" >"$samples/host.txt"
  echo 'app = "wattle-creek"' >"$samples/deploy/fly.toml"
  rev <<<'"aU7cG5fD1sH6nB4wYtR8zV2mLpQ9xJ3k" :drowssap_ptms' >"$samples/secret.txt"
  echo "the refuge Mulga-Downs keeps its files here" >"$samples/term.txt"

  # A secret of development is allowed in its two files, and nowhere else.
  mkdir -p "$samples/platform/config"
  rev <<<'"aU7cG5fD1sH6nB4wYtR8zV2mLpQ9xJ3kaU7cG5fD1sH6nB4w" :terces_gningis_nekot  ' |
    tee "$samples/platform/config/dev.exs" >"$samples/platform/config/prod.exs"

  # What the rules must let through: the addresses and the hosts of the
  # examples, and the version of a package.
  cat >"$samples/clean.txt" <<EOF
write to jane${at}example${dot}org, to JANE${at}Example${dot}ORG or to jane${at}refuge${dot}test
clone git${at}github${dot}com:example/example${dot}git
uses: actions/checkout${at}v7 and esbuild${at}0${dot}25${dot}4
open https://example${dot}fly${dot}dev/ and https://fly${dot}io/docs/
the refuge Mulga Creek has no file here
EOF

  echo "mulga-downs" >"$work/terms"
  write_rules "$work/terms"
  (cd "$samples" && scan dir . --redact --report-format json --report-path "$report" \
    >/dev/null 2>&1) || true

  # A finding of a file has the fingerprint `file:rule:line`.
  expect() {
    if ! grep -q "\"Fingerprint\": \"$2:$1:" "$report"; then
      echo "The rule $1 found nothing in the sample $2." >&2
      failed=1
    fi
  }

  expect rescord-email-address email.txt
  expect rescord-deployment-host host.txt
  expect rescord-fly-config deploy/fly.toml
  expect generic-api-key secret.txt
  expect rescord-private-term term.txt
  expect generic-api-key platform/config/prod.exs

  local clean
  for clean in clean.txt platform/config/dev.exs; do
    if grep -q "\"File\": \"$clean\"" "$report"; then
      echo "A rule found something in the sample $clean, which holds nothing to find." >&2
      failed=1
    fi
  done

  [ "$failed" -eq 0 ] || exit 1
  echo "Each rule of the scan finds its sample, and the examples pass."
}

if [ "$mode" = self-test ]; then
  self_test
  exit 0
fi

terms=${RESCORD_PRIVATE_TERMS:-$root/.private-terms}
if ! write_rules "$terms"; then
  echo "No list of private terms: the scan runs with the rules of the repository alone."
fi

cd "$root"

if [ "$mode" = staged ]; then
  scan git --staged . || {
    explain
    exit 1
  }
else
  scan git --log-opts=HEAD . || {
    explain
    exit 1
  }
fi
