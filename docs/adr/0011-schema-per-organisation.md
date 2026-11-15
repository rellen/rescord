# ADR 0011: Each organisation has its own schema

Status: accepted (chosen by the maintainer)

## Context

An organisation is a rescue or a refuge that uses Rescord, and it is one
tenant (`docs/domain.md`). Ash has two strategies for tenancy. With
`:attribute`, all tenants share the tables, and Ash adds a filter on a tenant
column to each query. With `:context`, the data layer keeps the tenants
apart; AshPostgres gives each tenant a schema of PostgreSQL.

What we read before the choice:

- The guide of AshPostgres to partitioned tables says: "Schema-based
  multitenancy is generally the recommended approach for multitenancy in
  AshPostgres." The guide of Ash calls the attribute strategy the simplest,
  with fewer advantages.
- The cost of a schema for each tenant is in its number. AshPostgres migrates
  the schemas one after the other, and each schema repeats each table.
  PostgreSQL states no limit on schemas. The sources that we read put the
  practical limit between a few hundred and about 10,000 schemas, and none
  of them measured it.
- The attribute strategy rests on Ash adding its filter to each query. An
  upsert did not, until Ash 3.37.2 (CVE-2026-96581).

The maintainer expects tens of organisations, and each needs about 44
resources (`docs/domain.md`, section 7).

## Decision

- Each organisation has its own schema. A resource that belongs to one
  organisation uses `multitenancy do strategy :context end`.
- `Organisation`, `User` and the token of a sign-in are not in a schema of an
  organisation. All organisations share them. A member, in the schema of an
  organisation, connects a user to that organisation.
- A dimension has values that all organisations share and values that one
  organisation adds. Where its tables are is not decided: `docs/domain.md`,
  section 7.2, gives the two ways.

## Consequences

- There are two sets of migrations: `priv/repo/migrations` for the shared
  tables, and `priv/repo/tenant_migrations` for the tables of an
  organisation. `mix ash.codegen` writes both, and both need review.
  `mix ash_postgres.migrate --tenants` runs the second set, one schema after
  the other.
- `Rescord.Repo` needs `all_tenants/0`, which returns the schema of each
  organisation.
- The resource `Organisation` uses `manage_tenant`, so that a new
  organisation gets its schema and its tables. An organisation that exists
  before a schema does gets none from a migration.
- A schema name matches `[a-zA-Z0-9_-]+`. A name made from an identifier must
  obey that.
- Each Ash call for a resource of an organisation carries the tenant. A
  LiveView takes the tenant from the member who is signed in, and passes it
  with the actor.
- An AshOban trigger on such a resource lists the tenants to run for
  (`list_tenants`). Oban's own table is shared.
- A report across organisations needs one query for each schema.
- To remove an organisation and its data, drop its schema.
- At 50 organisations the database holds about 2,200 tables. If the number
  of organisations reaches the high hundreds, read this decision again.
