#!/bin/sh
# The backup service of the Compose file (ADR 0050). It runs in the image of
# PostgreSQL 18, which has the pg_dump that the database needs, and works as
# bin/backup and bin/restore of the release do:
#
#   (no argument)    a backup at the start, and then each 24 hours
#   now              one backup
#   restore [dump]   the newest dump, or the one named, into an empty
#                    database, and the files back into the volume
#
# A backup is a dump of the database in ./backups/database, and a copy of
# each new file in ./backups/files. Each dump older than
# RESCORD_BACKUP_KEEP_DAYS days, 14 by default, is deleted. Keep .env with
# the backups: without RESCORD_KEY_SECRET, the keys of the transfers and the
# secrets of the settings do not open.
set -eu

dest=/backups
files=/files
keep=${RESCORD_BACKUP_KEEP_DAYS:-14}
umask 077

# Copies each file of $1 that $2 does not have. Rescord never changes a file,
# so a file that is there is the same. A key has no newline.
copy_new_files() {
  (cd "$1" && find . -type f) | while IFS= read -r file; do
    if [ ! -e "$2/$file" ]; then
      mkdir -p "$2/$(dirname "$file")"
      cp -p "$1/$file" "$2/$file"
    fi
  done
}

backup() {
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  dump="$dest/database/rescord-$stamp.dump"
  mkdir -p "$dest/database" "$dest/files"
  pg_dump --format=custom --file="$dump.partial"
  mv "$dump.partial" "$dump"
  copy_new_files "$files" "$dest/files"
  find "$dest/database" -name 'rescord-*.dump' -mtime +"$keep" -exec rm -f {} +
  echo "The backup is done: $dump, and the files."
}

restore() {
  if [ "$#" -eq 1 ]; then
    dump="$dest/database/$1"
  else
    dump=$(find "$dest/database" -name 'rescord-*.dump' | sort | tail -n 1)
  fi

  if [ -z "$dump" ] || [ ! -f "$dump" ]; then
    echo "There is no dump to restore in $dest/database." >&2
    exit 1
  fi

  pg_restore --exit-on-error --no-owner --no-privileges --dbname="$PGDATABASE" "$dump"
  copy_new_files "$dest/files" "$files"
  echo "The database is back from $dump, and the files are back."
}

case "${1:-}" in
  "")
    while :; do
      backup || echo "The backup failed. It runs again in 24 hours." >&2
      sleep 86400
    done
    ;;
  now) backup ;;
  restore)
    shift
    restore "$@"
    ;;
  *)
    echo "Give no argument, now, or restore [dump]." >&2
    exit 2
    ;;
esac
