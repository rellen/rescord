#!/usr/bin/env bash
# Runs a share of the parts of `mix test --partitions` on one machine, a few
# at once (ADR 0103):
#
#   scripts/test-in-parts.sh JOB JOBS EACH SLOTS [ARGUMENTS OF mix test...]
#
# The tests are cut into JOBS × EACH small parts. Job JOB (1 to JOBS) runs
# the parts (JOB - 1) × EACH + 1 to JOB × EACH, SLOTS of them at once: each
# slot takes the next part that no slot has taken yet, as soon as its part
# ends. Mix deals the test files out in turn, not by their time, so parts
# differ a lot; small parts in a queue keep each slot busy to the end,
# with no file of test times to keep up to date. CI runs it in each job of
# the tests. Most tests run one at a time (a test that makes an
# organisation is async: false), so one `mix test` keeps about one core
# busy, and a runner with 4 cores runs 4 slots.
#
# Slot k has the database rescord_test<k>, the port 4002 + k and a
# directory of files of its own (RESCORD_TEST_SLOT in config/test.exs). The
# script sets up each database and builds the assets once, before the parts
# start, and RESCORD_TEST_SET_UP tells the alias `test` that it is done: two
# builds of the assets at once would write the same files.
#
# It runs in the devenv shell, with PostgreSQL started. It shows the output of
# each part at the end, in the order of the parts, and fails when a part
# failed.
set -euo pipefail

stop() {
  echo "$1" >&2
  exit 2
}

[ "$#" -ge 4 ] || stop "Give JOB, JOBS, EACH and SLOTS, then the arguments of mix test."
for number in "$1" "$2" "$3" "$4"; do
  [[ $number =~ ^[1-9][0-9]*$ ]] || stop "JOB, JOBS, EACH and SLOTS are whole numbers from 1, not \"$number\"."
done
job=$1 jobs=$2 each=$3 slots=$4
shift 4
[ "$job" -le "$jobs" ] || stop "JOB is at most JOBS."

cd "$(dirname "$0")/../platform"
# The set-up runs in the environment of the tests, as in the alias `test`.
export MIX_ENV=test
total=$((jobs * each))
first=$(((job - 1) * each + 1))
last=$((job * each))
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT

echo "Parts $first to $last of $total, $slots at once."

# The database of each slot, side by side, and the assets once.
pids=()
for slot in $(seq 1 "$slots"); do
  RESCORD_TEST_SLOT=$slot mix ash.setup --quiet >"$logs/setup-$slot" 2>&1 &
  pids+=("$!")
done
failed=0
for index in "${!pids[@]}"; do
  if ! wait "${pids[$index]}"; then
    slot=$((index + 1))
    echo "::error::The database of slot $slot was not set up."
    cat "$logs/setup-$slot"
    failed=1
  fi
done
[ "$failed" -eq 0 ] || exit 1
mix assets.build

export RESCORD_TEST_SET_UP=1

# A slot takes a part by making its directory: mkdir makes it for one slot
# only, so no two slots run one part.
run_slot() {
  local slot=$1 part status
  shift
  for part in $(seq "$first" "$last"); do
    mkdir "$logs/taken-$part" 2>/dev/null || continue
    status=0
    RESCORD_TEST_SLOT=$slot MIX_TEST_PARTITION=$part \
      mix test --partitions "$total" "$@" >"$logs/test-$part" 2>&1 || status=$?
    echo "$status" >"$logs/status-$part"
  done
}

pids=()
for slot in $(seq 1 "$slots"); do
  run_slot "$slot" "$@" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done

for part in $(seq "$first" "$last"); do
  if [ "$(cat "$logs/status-$part" 2>/dev/null || echo none)" = 0 ]; then
    echo "::group::Part $part of $total passed: $(grep -m 1 -E '^(Finished in|There are no tests)' "$logs/test-$part" || true)"
    cat "$logs/test-$part"
    echo "::endgroup::"
  else
    echo "::error::Part $part of $total failed."
    cat "$logs/test-$part" 2>/dev/null || echo "The part did not run."
    failed=1
  fi
done
exit "$failed"
