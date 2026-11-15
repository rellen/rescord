# ADR 0020: Rate limits use AshRateLimiter and Hammer, with counts in ETS

Status: accepted (asked for by the maintainer, 15 November 2026)

## Context

A request for a sign-in link runs in a task and answers at once (ADR 0019).
The time of the answer then shows nothing, and nothing stops a flood of
requests: each one starts a task, and each one for a known address sends an
email. Other actions will need a limit too.

AshRateLimiter is the extension of Ash that limits how often an action runs.
It counts in a backend, and Hammer is the usual one. Hammer can keep its
counts in an ETS table, in Redis, or in other stores.

## Decision

- **An action gets its limit from `AshRateLimiter`**, in the `rate_limit`
  section of its resource.
- **`Rescord.RateLimit` is the backend**: a Hammer rate limiter that keeps
  its counts in an ETS table. The application starts it.
- `ash_rate_limiter` 2.0 and `hammer` 7.5 are both in `mix.exs`. Hammer is an
  optional dependency of the extension, so we name it ourselves.
- `Rescord.RateLimit` is an export of the core, so a domain can name it.

## Consequences

- The counts are in the memory of one node. Each node counts by itself, and a
  restart forgets the counts. That is sufficient for one node. More nodes
  need a shared store, which Hammer has.
- An action over its limit returns `AshRateLimiter.LimitExceeded`, which Ash
  reports as forbidden. For a request for a sign-in link that refusal stays
  inside the task, so the answer to the person does not change (ADR 0019).
- The limit of an action does not stop the tasks themselves: a request starts
  its task before the action runs. A limit for each client, before the task
  starts, can use `Rescord.RateLimit.hit/3` in a plug. It does not depend on
  the address, so it gives nothing away. Not decided: that limit, and the
  numbers of each limit.
- `Rescord.RateLimitTest` holds the three together: an action allows the
  calls within its limit, refuses the next one, counts each key by itself,
  and counts again after the period.
- Not tested: a limit on an action of a temporal resource. The change of the
  extension is probably not temporal safe (ADR 0012).
