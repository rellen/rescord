#!/usr/bin/env bash
# Tests an upgrade of Rescord with the Compose file (ADR 0051):
#
#   scripts/upgrade-test.sh OLD_IMAGE NEW_IMAGE
#   scripts/upgrade-test.sh ghcr.io/rellen/rescord:0.1.0 rescord:local
#
# It starts the database and OLD_IMAGE, makes data with the old version (the
# first root user, an organisation with its schema, and a file), starts
# NEW_IMAGE on the same volumes, and checks that the new version migrated
# the database and each organisation and that the data is there. It removes
# its containers and volumes at the end. The release workflow runs it with
# the image of the last release before it publishes a new one.
#
# The old version makes the data through its own functions, so the calls
# below must exist in each version that this script starts as OLD_IMAGE.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Give the old image and the new image: scripts/upgrade-test.sh OLD NEW" >&2
  exit 2
fi

old=$1
new=$2
root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
work=$(mktemp -d)
project="rescord-upgrade-$$"

cp "$root/deploy/compose/compose.yaml" "$root/deploy/compose/Caddyfile" \
  "$root/deploy/compose/backup.sh" "$work/"

secret() { head -c 48 /dev/urandom | base64 | tr -d '\n'; }
cat > "$work/.env" <<EOF
RESCORD_IMAGE=$old
PHX_HOST=localhost
CADDY_TLS=internal
POSTGRES_PASSWORD=$(secret | tr -dc 'A-Za-z0-9')
SECRET_KEY_BASE=$(secret)
TOKEN_SIGNING_SECRET=$(secret)
RESCORD_KEY_SECRET=$(secret)
RESCORD_SMTP_HOST=localhost
RESCORD_SMTP_TLS=none
RESCORD_MAIL_FROM=rescord@rescord.test
EOF

compose() { docker compose -p "$project" --project-directory "$work" "$@"; }

cleanup() {
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

wait_for_health() {
  for _ in $(seq 120); do
    if compose exec -T rescord curl -fsS http://localhost:4000/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "Rescord did not answer its health check. Its log:" >&2
  compose logs --tail 80 rescord >&2
  return 1
}

sql() { compose exec -T db psql -U rescord -d rescord -tAc "$1"; }

echo "== The old version: $old"
compose up -d db rescord
wait_for_health

compose exec -T rescord bin/bootstrap-root first@rescord.test
compose exec -T rescord bin/rescord eval '
  {:ok, _} = Application.ensure_all_started(:rescord)
  {:ok, [root]} = Rescord.Accounts.roots(authorize?: false)

  {:ok, _} =
    Rescord.Accounts.create_organisation(
      %{name: "Upgrade Refuge", short_name: "upgrade-refuge", time_zone: "Australia/Brisbane"},
      actor: root
    )'
compose exec -T rescord sh -c 'echo "a file of the old version" > /var/lib/rescord/files/upgrade-probe.txt'
schema=$(sql "select 'org_' || id from organisations where short_name = 'upgrade-refuge'")
tables_before=$(sql "select count(*) from information_schema.tables where table_schema = '$schema'")
echo "The old version made the organisation, with $tables_before tables in $schema."

echo "== The new version: $new"
sed -i "s#^RESCORD_IMAGE=.*#RESCORD_IMAGE=$new#" "$work/.env"
compose up -d rescord
wait_for_health

failed=0
expect() {
  if [ "$2" = "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: $2, and not $3" >&2
    failed=1
  fi
}

expect "the root user" "$(sql 'select count(*) from users where is_root')" 1
expect "the organisation" "$(sql "select count(*) from organisations where short_name = 'upgrade-refuge'")" 1
expect "the file" "$(compose exec -T rescord cat /var/lib/rescord/files/upgrade-probe.txt)" "a file of the old version"

# bin/check of the new version reads each migration of the database and of
# each organisation. Its mail fails here, with no SMTP server.
report=$(compose exec -T rescord bin/check 2>/dev/null || true)
expect "the migrations" "$(printf '%s\n' "$report" | grep -c '^ok    migrations each migration has run' || true)" 1
expect "the root user is kept" "$(compose exec -T rescord bin/bootstrap-root second@rescord.test 2>/dev/null | grep -c 'has a root user already' || true)" 1

if [ "$failed" -ne 0 ]; then
  printf '%s\n' "$report" >&2
  compose logs --tail 80 rescord >&2
  exit 1
fi

echo "The upgrade from $old to $new keeps the data."
