#!/usr/bin/env bash
# Runs several parts of `mix test --partitions` side by side on one machine
# (ADR 0103), each with a database of its own:
#
#   scripts/test-in-parts.sh JOB JOBS EACH [ARGUMENTS OF mix test...]
#
# The tests are cut into JOBS × EACH parts. Job JOB (1 to JOBS) runs the
# parts (JOB - 1) × EACH + 1 to JOB × EACH, EACH of them at once. CI runs it
# in each job of the tests. Most tests run one at a time (a test that makes
# an organisation is async: false), so one `mix test` keeps about one core
# busy, and a runner with 4 cores can run several.
#
# Each part gets its database rescord_test<k> (MIX_TEST_PARTITION). The
# script sets up each database and builds the assets once, before the parts
# start, and RESCORD_TEST_SET_UP tells the alias `test` that it is done: two
# builds of the assets at once would write the same files.
#
# It runs in the devenv shell, with PostgreSQL started. It shows the output of
# each part when the part ends, and fails when one part failed.
set -euo pipefail

stop() {
  echo "$1" >&2
  exit 2
}

[ "$#" -ge 3 ] || stop "Give JOB, JOBS and EACH, then the arguments of mix test."
for number in "$1" "$2" "$3"; do
  [[ $number =~ ^[1-9][0-9]*$ ]] || stop "JOB, JOBS and EACH are whole numbers from 1, not \"$number\"."
done
job=$1 jobs=$2 each=$3
shift 3
[ "$job" -le "$jobs" ] || stop "JOB is at most JOBS."

cd "$(dirname "$0")/../platform"
# The set-up runs in the environment of the tests, as in the alias `test`.
export MIX_ENV=test
total=$((jobs * each))
first=$(((job - 1) * each + 1))
last=$((job * each))
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

echo "Parts $first to $last of $total, $each at once."

# The databases, side by side, and the assets once.
pids=()
for part in $(seq "$first" "$last"); do
  MIX_TEST_PARTITION=$part mix ash.setup --quiet >"$logs/setup-$part" 2>&1 &
  pids+=("$!")
done
failed=0
for index in "${!pids[@]}"; do
  if ! wait "${pids[$index]}"; then
    part=$((first + index))
    echo "::error::The database of part $part was not set up."
    cat "$logs/setup-$part"
    failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
mix assets.build

export RESCORD_TEST_SET_UP=1
pids=()
for part in $(seq "$first" "$last"); do
  MIX_TEST_PARTITION=$part mix test --partitions "$total" "$@" >"$logs/test-$part" 2>&1 &
  pids+=("$!")
done

# Each part in the order the parts end would need `wait -n` and its pid;
# in the order of the parts is enough, since the log shows all at the end.
for index in "${!pids[@]}"; do
  part=$((first + index))
  if wait "${pids[$index]}"; then
    echo "::group::Part $part of $total passed: $(grep -m 1 '^Finished in' "$logs/test-$part" || true)"
    cat "$logs/test-$part"
    echo "::endgroup::"
  else
    echo "::error::Part $part of $total failed."
    cat "$logs/test-$part"
    failed=1
  fi
done
exit "$failed"
