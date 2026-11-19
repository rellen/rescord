# ADR 0041: The attachments of the journal

Status: accepted. It builds ADR 0038.

## Context

ADR 0038 chose the stores of the files. This record says how a journal
entry gets its files, how a person reads one, and what the tests use.

## Decision

- **`Rescord.Storage`** is a behaviour with `put/3`, `get/1` and
  `delete/1`. `config :rescord, :storage` names the module:
  `Rescord.Storage.S3` in development and production, and
  `Rescord.Storage.Disk` in the tests. `Rescord.Storage.key/2` makes each
  key from the id of the organisation, a word and an id, so no key comes
  from what a person sends, and no key leaves its organisation.
- **`Rescord.Storage.S3`** signs each request with `req_s3`. For an
  endpoint that is not on `s3.amazonaws.com`, `req_s3` puts the bucket in
  the path, which Garage takes. Nobody has checked Tigris with a request
  in that style yet: do so before production. The module gives `req_s3` its
  keys, so `req_s3` never reads the `AWS_` variables. Production reads
  `RESCORD_S3_ENDPOINT` (the default is Tigris, `https://t3.storage.dev`),
  `RESCORD_S3_REGION` (the default is `auto`), `RESCORD_S3_BUCKET`,
  `RESCORD_S3_ACCESS_KEY_ID` and `RESCORD_S3_SECRET_ACCESS_KEY`.
  Development uses the Garage of devenv and its fixed key.
- **`Rescord.Journal.Attachment`** is the record of a file: the entry, the
  name, the type, the size, the key and the author. It is not temporal.
  `attach` takes the bytes. `StoreAttachment` reads the type from the
  first bytes and not from the name: JPEG, PNG, GIF, WebP or PDF. It
  refuses another type, an empty file, and a file of more than 20 MB, and
  it puts the file in the store in the transaction of the record.
- **A new entry takes its files**, five at most, through the upload of
  LiveView. `Rescord.Journal.write_entry_with_files/3` writes the entry and
  each file in one transaction, so a refused file writes no entry.
- **A person reads a file at `/o/<short name>/attachments/<id>`.**
  `RescordWeb.AttachmentController` reads the record with the grants of the
  person, and sends the bytes with the type that Rescord found,
  `nosniff` from the browser pipeline, a `sandbox` content security policy
  and no cache. The read with the grants of the person is a second guard,
  behind the check that the person is a member: each role reads the files,
  so a mutation that drops it leaves each test green. A file that
  the person cannot read and a file that is not there get one answer.
- **The grants.** Each role reads the files. The power `:journal` attaches
  a file and takes off a file that the person attached. The power
  `:correct_journal` takes off each file. A removal archives the record,
  and the file stays in the store.
- **The tests** keep the files in the temporary directory of each test
  (`Rescord.StorageFixtures.disk_store!/1`). A test of `Rescord.Storage.S3`
  gives it `req_options: [plug: {Req.Test, Rescord.Storage.S3}]` and reads
  the signed request.

## Consequences

- The store was checked by hand against Garage 2.5 on 19 November 2026:
  a put, a get, a delete, and a delete of a file that was gone. No test
  runs against a real service.
- The Garage module of devenv binds its internal port to `[::]`. A machine
  with no IPv6 cannot start it, and the module has no option for that
  address.
- A file that the store took, in a transaction that the database then
  refused, stays in the store with no record. Nothing names it.
- A file goes through Rescord on its way out. A presigned link to the store
  can replace that later, if the files get large or many.
- A person attaches files to a new entry only. The form of an addendum
  takes no file yet, so a file for an entry that exists goes with a new
  entry.
