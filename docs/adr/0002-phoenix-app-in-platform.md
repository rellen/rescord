# ADR 0002: The Phoenix application lives in `platform/`

Status: accepted (chosen by the maintainer)

## Context

The repository holds the toolchain and the documentation beside the
application, and may hold more parts that are not Elixir applications.

## Decision

- The Mix project lives in `platform/`. The OTP application is `:rescord`,
  with the modules `Rescord` and `RescordWeb`.
- It was generated with
  `mix igniter.new platform --with phx.new --with-args="--app rescord --module Rescord" --install ash,ash_postgres,ash_phoenix --no-git --yes`.
- The repository root holds no `mix.exs`. An umbrella project does not fit,
  because the other parts are not Elixir applications.

## Consequences

- Mix reads every path from `platform/`, so the tooling works unchanged; run
  `mix` there.
- CI, when it exists, sets `platform/` as the working directory of each
  Elixir step.
