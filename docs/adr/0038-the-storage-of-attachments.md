# ADR 0038: The storage of attachments

Status: accepted (the answers are from the maintainer, 18 November 2026).
Nothing is built yet.

## Context

A journal entry can have an attachment, such as a photo or the report of a
vet. The maintainer answered:

- The files are in storage that is compatible with S3, and `req_s3`, a
  plugin of `Req`, reads it.
- Production probably uses Tigris. Its endpoint is `https://t3.storage.dev`,
  and its region is `auto`.
- A machine for development runs Garage. MinIO is no longer an option:
  nixpkgs removed it on 11 October 2026, because its maker abandoned the
  open source edition.
- The tests use a store that keeps the files in a temporary directory.

## Decision

- **A behaviour names what Rescord needs from a store**, for example
  `Rescord.Storage`: put a file, get it, delete it, and give a link that
  works for a short time. The application reads the module of the store
  from its configuration.
- **`Rescord.Storage.S3`** implements it with `req_s3`. The endpoint, the
  region, the bucket and the keys come from the environment at run time,
  so one module serves Tigris and Garage.
- **`Rescord.Storage.Disk`** implements it in a directory. The tests use it
  with a temporary directory for each test, so a test needs no service and
  shares no file.
- **devenv runs Garage 2** with `services.garage`, which applies the layout
  and makes the bucket. A fixed key for development goes in its
  `afterStart`.
- The record of an attachment, with its name, its type and its size, is in
  the schema of the organisation. The key of the file in the store starts
  with the id of the organisation, so the files of two organisations never
  share a key.

## Consequences

- No test checks what `Rescord.Storage.S3` sends to a real service. A test
  that runs against Garage can come later.
- The browser can send a file straight to the store with a presigned link,
  or through Rescord. That choice belongs to the work on attachments.
- A file in the store has no period: a correction of an entry keeps the old
  file, and only the record of the attachment changes.
