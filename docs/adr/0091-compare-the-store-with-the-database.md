# ADR 0091: Compare the files of the store with the records

Status: accepted (the maintainer chose the design of issue 15 and said to
build it, 28 November 2026). It adds to ADR 0038, ADR 0041, ADR 0044 and
ADR 0059.

## Context

A record names its file by a key (`Rescord.Storage`). Rescord writes the
record first and puts the file in the store after it, inside the
transaction. So an upload leaves no record with no file. The other way
round does happen: a file can stay in the store with no record.

1. The thumbnail fails after the photo went in. The record rolls back,
   and the photo stays.
2. A later file of the same journal entry is refused. The entry rolls
   back, and each file before it stays, with its thumbnail.
3. A file in the middle of a transfer fails. The transfer rolls back, and
   each file that was copied before stays.
4. Anything else fails between a put and the commit: the commit itself, or
   the process of the page when the person closes the tab.

ADR 0041 accepted this: "A file that the store took, in a transaction that
the database then refused, stays in the store with no record. Nothing
names it." No page shows such a file, and nothing deletes it: the only
delete of a file in the application is the test file of `bin/check`. So
an operator could not see how many there are, or how much space they
take, and `bin/move-storage` carries them to the new store.

The opposite fault had no check either. ADR 0059 says of the move: "The
command does not compare the store with the database. A file that the old
store lost before the move is missing after it too."

Three facts make a comparison simple:

- Rescord deletes no record that names a file. A removal archives the
  row, and a temporal resource keeps each version as a row. So the tables
  hold each key that the history can name.
- A key never changes: no action takes a key as input.
- A key starts with the id of its organisation.

## Decision

- **`bin/check-files`** (`rescord-check-files` on NixOS) compares the
  store of the server with the database, and prints a report
  (`Rescord.Release.check_files/1`). It is not a part of `bin/check`,
  which is quick: this command lists each file of the store and reads
  each file table of each organisation.
- **It changes nothing.** It deletes no file, and it writes no record.
  This is the decision of the maintainer for this step. A delete of the
  leftovers needs its own design: the age of a file, so that it never
  deletes a file of an upload that runs, a rule for `bin/move-storage`,
  which relies on the fact that no file is deleted while it runs, and a
  decision for a bucket that keeps versions.
- **A store lists its files with their sizes.** The new callback
  `files/0` of `Rescord.Storage` returns `{name, size}` for each file. The
  directory reads the size from the directory entry, and the bucket takes
  it from ListObjectsV2, so no file is read for it. `list/0` gives the
  same names as before. A list of a bucket with no size for an object is
  refused by `files/0`, and `list/0` still names its keys.
- **Each domain says which keys its records name.** `Rescord.Journal`,
  `Rescord.Photos`, `Rescord.Expenses` and `Rescord.Transfers` each have
  `file_keys/1`, for the id of an organisation. For a resource with the
  attributes `key` and `thumbnail_key`, `Rescord.Storage.Named.keys/3`
  reads the table itself, as `Rescord.Vault` reads its tables: with no
  actor, no filter of the archive and no instant, so a removed record and
  each old version count. A transfer names
  `<organisation>/transfers/<transfer>/<file>` for each file of its copy,
  in any state, for the refuge that received it. An export keeps no file
  on this server.
- **A test keeps that list whole.** `Rescord.Release.FilesTest` fails for
  a resource with the text attribute `key` whose domain is not asked, or
  whose `file_keys/1` does not read its table.
- **The command decides by what the records say**, and not by the shape
  of a key (`Rescord.Storage.Compare`). Each name of the store is in one
  group:

  | Group | What it is |
  | --- | --- |
  | named | a record names it |
  | leftover | a key of an organisation of this server that no record names |
  | unknown | a key whose first segment is no organisation of this server, such as the test file of a `bin/check` that stopped |
  | other | a name that is no key, such as the `lost+found` of a volume, or the part of a put that stopped |

  And a key that a record names and the store does not have is missing:
  the report says `FAIL`, with the kind of the record, its id and the id
  of its organisation.
- **The report says sizes** (the maintainer asked for them in the first
  version): the size of the store, of the named files, of each group, and
  of each leftover that it names.
- **The report prints ids, keys and sizes**: no name of a file, no
  caption, and nothing that a person typed. It names the first 20 files
  of a group, and `--all` names each one.
- **The exit code** is 0 when the store has each file that a record
  names, with leftovers or with none: a leftover does no harm, so it is a
  note. It is 1 when a file is missing. There is no option that makes a
  leftover a failure. It is 2 when the command could not compare: the
  store did not list its files, the database did not answer, a migration
  of this version has not run, or the argument is not `--all`.
- **The store is listed first, and the database is read after it.** A
  file is in the store before its transaction commits, so an upload that
  ends between the two is named, and is no leftover. An upload that is
  still open is a false leftover, and the report says so: "Run the
  command again: a leftover is in both runs."
- **A file that the list does not have is asked for by itself.** A file
  of an upload that started after the list is named by a record and is
  not in the list. So the command asks the store for each such file
  before it calls it missing (`Rescord.Storage.Compare.confirm/2`). A
  file that is there counts as named. When the store gives another fault
  than "not there", the report says that it did not learn whether the
  file is there.
- **It starts the repository with a small pool and Req**, and not the
  application, as `bin/check` does. An operator runs it beside a server
  that works.

## Consequences

- An operator sees how many leftovers a store has and how much space
  they take, and deletes them with the tools of the store, when the
  space matters. Rescord still deletes none.
- A check after a restore, or after `bin/move-storage`, says whether
  each file that a record names is there. It does not read the files: a
  file with the wrong bytes under the right key passes.
- The keys are in memory while the command runs: about 100 bytes for
  each, so 100,000 files are about 10 MB. It reads one list of the store
  (1000 keys for each request to a bucket), each file table of each
  organisation, and the copy of each transfer that an organisation
  received.
- A store that lost many files gets one request for each of them, four
  at one time, and a file that is there after all is read whole for the
  answer: the behaviour of a store has no question "is it there".
- A new resource that keeps a file holds its key in `key`, and its
  domain gets `file_keys/1` and a place in
  `Rescord.Release.Files.domains/0`. The test names the resource until
  then. A resource that names a file in another way, as a transfer does
  in its copy, is not found by the test: its author adds its keys by
  hand.
- When a transfer copies its files in a job (issue 16), a transfer that
  is still on its way names files that are not in the store yet. That
  work must leave such a transfer out of `Rescord.Transfers.file_keys/1`
  until its files are there. ADR 0100 did: a transfer with sources names
  only the files that the job copied.
- The tests run the command against the directory and against
  `Rescord.FakeS3`, with records that real actions made: each of the four
  faults above, a removed attachment and receipt, the versions of a
  photo, a photo of a journal entry, and a transfer in each state. The
  NixOS test runs `rescord-check-files` on a machine. No request went to
  a bucket of a provider.
