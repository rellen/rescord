#!/usr/bin/env bash
# Starts a run of CI for the newest commit of main, when main has waited too
# long for a result (ADR 0078):
#
#   scripts/ci-catch-up.sh               starts the run when the rule says so
#   scripts/ci-catch-up.sh --after N     waits N minutes and not 60; 0 is "now"
#   scripts/ci-catch-up.sh --dry-run     says what it would do, and starts nothing
#   scripts/ci-catch-up.sh --self-test   shows that the rule decides each case
#
# A push to main cancels the run of CI of the push before it. When pushes
# come faster than a run takes, no run ends, and nobody knows whether main
# passes. The workflow `ci-catch-up.yml` runs this script on a schedule.
#
# A run has a result when it ended as a success, a failure, a timeout or a
# failure to start. A cancelled run has none. The rule reads the runs of
# `ci.yml` on main:
#
#   * the newest commit has a result: nothing to do;
#   * a run that no push cancels is on its way: nothing to do. That is a run
#     of the event workflow_dispatch on main (the concurrency of `ci.yml`);
#   * no run was started after the last result: nothing to do, because the
#     newest commit asked for none;
#   * the oldest run after the last result started less than N minutes ago:
#     wait, because the run of the newest push may still end;
#   * otherwise: start a run of `ci.yml` on main, as workflow_dispatch.
#
# It needs `gh` and `jq`, a token in GH_TOKEN that may read the contents and
# write the actions, and the repository in GITHUB_REPOSITORY (owner/name).
set -euo pipefail

workflow=ci.yml
branch=main

stop() {
  echo "$1" >&2
  exit 2
}

# The decision, as "word<TAB>sentence". The word is nothing, wait or run.
# Reads the runs (the array `workflow_runs` of the API) on standard input.
#   $1  the newest commit of the branch
#   $2  the time now, in seconds since 1970
#   $3  the minutes that main may wait for a result
decide() {
  jq -r --arg head "$1" --argjson now "$2" --argjson after "$3" '
    def has_result:
      .status == "completed"
      and (.conclusion | IN("success", "failure", "timed_out", "startup_failure"));
    def kept: .event == "workflow_dispatch";

    (map(. + {at: (.created_at | fromdateiso8601)}) | sort_by(.at) | reverse) as $runs
    | ($runs | map(select(has_result))) as $results
    | if any($results[]; .head_sha == $head) then
        "nothing\tThe newest commit of main has a result."
      elif any($runs[]; kept and .status != "completed") then
        "nothing\tA run that no push cancels is on its way."
      else
        (($results[0].at) // 0) as $last
        | ($runs | map(select(.at > $last) | .at)) as $waiting
        | if ($waiting | length) == 0 then
            "nothing\tNo run was started for the newest commit of main."
          else
            ((($now - ($waiting | min)) / 60) | floor) as $minutes
            | if $minutes >= $after then
                "run\tMain has waited \($minutes) minutes for a result."
              else
                "wait\tMain has waited \($minutes) minutes for a result, which is less than \($after)."
              end
          end
      end
  '
}

self_test() {
  local failed=0
  # 12:00:00 UTC on 28 November 2026.
  local now=1795867200

  # A run: "sha event status conclusion minutes-before-now". A conclusion
  # of "-" is none.
  runs() {
    local run sha event status conclusion minutes
    for run in "$@"; do
      read -r sha event status conclusion minutes <<<"$run"
      [ "$conclusion" != - ] || conclusion=
      jq -n --arg sha "$sha" --arg event "$event" --arg status "$status" \
        --arg conclusion "$conclusion" --argjson at "$((now - minutes * 60))" \
        '{head_sha: $sha, event: $event, status: $status,
          conclusion: (if $conclusion == "" then null else $conclusion end),
          created_at: ($at | todateiso8601)}'
    done | jq -s .
  }

  expect() {
    local name=$1 want=$2 head=$3 after=$4 got
    shift 4
    got=$(runs "$@" | decide "$head" "$now" "$after" | cut -f1)
    if [ "$got" = "$want" ]; then
      echo "ok    $name"
    else
      echo "FAIL  $name: the rule said \"$got\", and not \"$want\"" >&2
      failed=1
    fi
  }

  expect "the newest commit passed" nothing c 60 \
    "c push completed success 90" "b push completed cancelled 95"
  expect "the newest commit failed, which is a result" nothing c 60 \
    "c push completed failure 90" "b push completed cancelled 95"
  expect "a quiet push runs, after an old result" wait c 60 \
    "c push in_progress - 5" "a push completed success 300"
  expect "pushes cancelled each other for more than an hour" run d 60 \
    "d push in_progress - 3" "c push completed cancelled 20" \
    "b push completed cancelled 70" "a push completed success 80"
  expect "pushes cancelled each other for less than an hour" wait d 60 \
    "d push in_progress - 3" "c push completed cancelled 20" \
    "b push completed cancelled 50" "a push completed success 80"
  expect "the run of the newest commit was cancelled by hand, an hour ago" run c 60 \
    "c push completed cancelled 61" "a push completed success 300"
  expect "no run has a result yet" run c 60 \
    "c push in_progress - 3" "b push completed cancelled 90"
  expect "a kept run is on its way" nothing d 60 \
    "d push in_progress - 3" "c workflow_dispatch in_progress - 10" \
    "b push completed cancelled 90" "a push completed success 95"
  expect "a kept run waits for its turn" nothing d 60 \
    "d workflow_dispatch queued - 1" "b push completed cancelled 90"
  expect "a kept run gave an older commit its result, a while ago" wait d 60 \
    "d push in_progress - 3" "c push completed cancelled 40" \
    "b workflow_dispatch completed success 45" "b push completed cancelled 100"
  expect "a kept run gave the newest commit its result" nothing b 60 \
    "b workflow_dispatch completed failure 45" "b push completed cancelled 100"
  expect "a kept run that was cancelled gives no result" run b 60 \
    "b workflow_dispatch completed cancelled 45" "b push completed cancelled 100"
  expect "the newest commit asked for no run" nothing c 60 \
    "b push completed success 200"
  expect "a timeout is a result" nothing c 60 \
    "c push completed timed_out 90"
  expect "a skipped run is no result" run c 60 \
    "c push completed skipped 90"
  expect "now: a cancelled run of a minute ago" run c 0 \
    "c push completed cancelled 1" "a push completed success 300"
  expect "now: the newest commit has its result" nothing c 0 \
    "c push completed success 1"
  expect "no run at all" nothing c 60

  [ "$failed" -eq 0 ] || exit 1
}

after=60
dry_run=false
while [ "$#" -gt 0 ]; do
  case $1 in
    --self-test)
      self_test
      exit 0
      ;;
    --dry-run) dry_run=true ;;
    --after)
      [ "$#" -ge 2 ] && [[ $2 =~ ^[0-9]+$ ]] || stop "Give the minutes after --after, such as 60."
      after=$2
      shift
      ;;
    *) stop "Give no argument, --after MINUTES, --dry-run or --self-test." ;;
  esac
  shift
done

[ -n "${GITHUB_REPOSITORY:-}" ] || stop "Set GITHUB_REPOSITORY to the repository, as owner/name."

head=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/$branch" --jq .object.sha)
decision=$(
  gh api -X GET "repos/$GITHUB_REPOSITORY/actions/workflows/$workflow/runs" \
    -f branch="$branch" -F per_page=100 --jq .workflow_runs |
    decide "$head" "$(date +%s)" "$after"
)
word=${decision%%$'\t'*}
sentence=${decision#*$'\t'}

case $word in
  nothing | wait) outcome="$sentence No run of CI was started." ;;
  run)
    if [ "$dry_run" = true ]; then
      outcome="$sentence A run of CI would start now."
    else
      gh workflow run "$workflow" --repo "$GITHUB_REPOSITORY" --ref "$branch"
      outcome="$sentence A run of CI was started for the newest commit of $branch."
    fi
    ;;
  *) stop "The rule gave no decision: \"$decision\"." ;;
esac

echo "The newest commit of $branch is $head. $outcome"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "The newest commit of \`$branch\` is \`$head\`. $outcome" >>"$GITHUB_STEP_SUMMARY"
fi
