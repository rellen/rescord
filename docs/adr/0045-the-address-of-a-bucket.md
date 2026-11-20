# ADR 0045: The address of a bucket

Status: accepted (the maintainer, 20 November 2026).

## Context

A service that is compatible with S3 takes the name of a bucket in the path
of an address (`https://s3.example.org/rescord/KEY`), in the host
(`https://rescord.s3.example.org/KEY`), or both. `req_s3` puts it in the
host for Amazon alone, and in the path for every other endpoint.

Tigris takes only the host for a bucket made after 19 February 2025
("For new buckets, we will stop supporting path style URLs", the Tigris
blog of that day). So Rescord could not use a new bucket of Tigris, which
ADR 0038 names for production. Garage and MinIO, which a rescue may run on
its own server, take the path as they are set up by default, and the host
only with a domain of their own.

## Decision

- **`RESCORD_S3_ADDRESSING` chooses**, as `:addressing` of
  `Rescord.Storage.S3`: `path`, the default, or `virtual`.
- **`path` keeps the `s3://` address of `req_s3`**, which development and
  its tests use.
- **`virtual` builds the address itself**: the bucket and a dot before the
  host of the endpoint, and the key as the path.
- **The store names the service `s3` in the signature.** Req finds the
  service from the host of Amazon alone, and `req_s3` names it for an
  `s3://` address alone.

## Consequences

- An operator of Tigris sets `RESCORD_S3_ADDRESSING=virtual`, with the
  endpoint `https://t3.storage.dev` and the region `auto`.
- With `virtual`, the name of the bucket is part of a host name, so it has
  no dot: a certificate for `*.t3.storage.dev` does not cover a name with
  two more parts.
- Both styles were run against Garage 2.5 with real signatures, and each
  put, got and deleted a file. A wrong secret got 403 in both. No request
  went to Tigris itself: that needs keys of a Tigris account.
