# ADR 0059: Move the files to another store

Status: accepted (the maintainer asked for it, 27 November 2026). It adds
to ADR 0038, ADR 0044 and ADR 0045.

## Context

A server keeps its files in a directory or in a bucket of S3
(`RESCORD_STORAGE`). A rescue that starts with a directory can want a
bucket later, and one with a bucket can want its files on its own disk.
Nothing moved the files. A change of the setting alone left each photo
and each PDF behind, and the pages showed none of them.

The record of a file holds its key and no word about the store, so the
database needs no change: the same key must give the same bytes in the new
store.

## Decision

- **`bin/move-storage disk s3`, or `s3 disk`**, copies each file of one
  store into the other (`Rescord.Release.move_storage/2`,
  `Rescord.Storage.Move`). The operator names both stores, so the command
  does not depend on `RESCORD_STORAGE`, which changes in the middle of a
  move.
- **A store lists its files**: `list/0` is in the behaviour
  `Rescord.Storage`. The directory walks its tree. The bucket asks
  ListObjectsV2, page after page, and reads the XML with the parser of
  Erlang, with no entity and nothing from outside the document. The move
  copies what the store holds, and not what the database names: a file of
  a corrected entry has no current record, and the history still shows it.
- **Each copy is checked.** A file that the new store does not list is
  put there, read back, and compared byte for byte with the file of the
  old store. A file that the new store lists is read from both and
  compared: the same bytes need no copy.
- **A run deletes nothing, and writes over no file that the new store
  lists.** Other bytes under the same key are a fault that the report
  names, and both files stay. The operator deletes the old store, when the
  new one has served for a time.
- **A run is safe to start again.** It copies only what is missing, so a
  run that stopped, or one beside a server that works, is finished by the
  next run. Rescord never changes a file under a key, and no page deletes
  one, so a file that was copied is still right.
- **The directory takes a file whole.** `Rescord.Storage.Disk.put/3`
  writes beside the key, under a name with a dot, syncs, and then gives
  the file its name. A put that stops leaves no half of a file under a
  key, which a later run would take for a file with other bytes.
- **A name that is no key stays** (`Rescord.Storage.key?/1`): the
  `lost+found` of a volume, or an object that another program put in the
  bucket. The report counts and names them.
- **The command reads the settings of both stores.** The script sets
  `RESCORD_BOTH_STORES`, and then `config/runtime.exs` requires
  `RESCORD_FILES_DIR` and each `RESCORD_S3_` setting. A server reads the
  settings of its own store alone, as before.
- **The command starts Req and nothing else**: no database, and not the
  application.
- **The type of a file in the bucket** is the type of its first bytes,
  because a directory keeps no type. Rescord does not read it back: the
  record of the file holds the type.
- The NixOS module installs `rescord-move-storage`.

## Consequences

- An operator copies while Rescord runs, changes `RESCORD_STORAGE`, starts
  Rescord again, and runs the command one more time for the files that
  arrived in between. `docs/self-hosting.md` has the steps.
- Each run reads each file of both stores, so a second run takes about as
  long as the first one, less the writes. Four files move at one time,
  each in memory, and a file is 20 MB at most.
- The tests run both directions against `Rescord.FakeS3`, a service in
  the memory of the test that gets each request that the store signs. Both
  directions were also run against Garage 2.5 with real signatures: 1204
  files, more than one page of a list, with the bucket in the path and in
  the host, and `diff -r` found the directory that came back the same. No
  request went to Tigris itself.
- The command does not move between two buckets: the settings name one
  bucket. A move from a bucket to another goes through a directory.
- A backup does not copy a bucket (ADR 0050). After a move to S3, the
  backup of the files is the versions of the provider.
- The command does not compare the store with the database. A file that
  the old store lost before the move is missing after it too.
