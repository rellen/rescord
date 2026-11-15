# ADR 0016: A local value of a dimension is in the schema of its organisation

Status: accepted (chosen by the maintainer, 15 November 2026)

## Context

Thirteen dimensions, such as the species and the breed, have shared values
and local values (`docs/domain.md`, section 7.2). All organisations share the
base list, and an organisation can add values for its own use. ADR 0011 left
open where a local value is stored. There were two ways:

- One shared resource for each dimension, where a local value names the
  organisation that owns it. Each schema then holds 44 resources.
- A shared base list, and a list in the schema of each organisation. Each
  schema then holds 13 more resources: 57.

The first way has fewer resources. It keeps the local values of all
organisations in one table, apart by an attribute only. ADR 0011 chose a
schema for each organisation so that the data of an organisation is apart by
more than an attribute.

## Decision

- A local value of a dimension is in the schema of the organisation that
  added it.
- Each of the 13 dimensions has two resources: the base list, which all
  organisations share, and the list of the organisation, in each schema.
- The list of the organisation uses `Rescord.Resource` with its defaults. The
  base list uses `shared?: true`.

## Consequences

- Each schema holds 57 resources and about 58 tables, in the estimate of
  `docs/domain.md`. For 50 organisations that is about 2,900 tables, which
  gives PostgreSQL no difficulty.
- No query can read the local values of another organisation by a mistake in
  a filter: they are in another schema.
- A value of a dimension can be in one of two tables. How a resident names
  it is open. `docs/domain.md`, section 7.2, proposes that the list of the
  organisation holds each value that the organisation uses, so that a
  resident names one table.
- A report over all organisations, for example a count of residents for each
  local breed, reads each schema in turn.
