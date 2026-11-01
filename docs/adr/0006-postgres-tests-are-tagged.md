# ADR 0006: Tests that need Postgres carry the `:postgres` tag

Status: accepted

## Context

Some environments have no PostgreSQL, such as a cloud session that runs as
root. A test whose setup checks out the SQL sandbox fails there after a
timeout, and `mix test` cannot even start, because its alias runs
`ash.setup` first.

## Decision

- The `using` blocks of `Rescord.DataCase` and `RescordWeb.ConnCase` set
  `@moduletag :postgres`. Their setup checks out the SQL sandbox, so every
  module that uses one needs Postgres, and no other module does.
- A test that does not need Postgres uses `ExUnit.Case`.
- Without Postgres, call the test task directly, which skips the alias:
  `MIX_ENV=test mix run -e 'Mix.Tasks.Test.run(System.argv())' -- --exclude postgres`.

## Consequences

- A new module that uses one of the cases gets the tag, so no list of files
  falls behind.
- `mix test` still runs every test.
