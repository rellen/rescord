# ADR 0066: Each domain checks alias references

Status: accepted (the maintainer chose proposal B1 of ADR 0062 on
28 November 2026). It adds to ADR 0009 and closes one of its open questions.

## Context

ADR 0009 gave each Ash domain a boundary. `ash_boundary` checks a call from
a domain into another one. It does not check an alias reference unless the
domain sets `check [aliases: true]`. A relationship names its destination
as an alias, and so does a signal listener (`from SomeDomain.Signals`). A
resource could thus name an internal module of any domain, in the `deps` of
its domain or not, and the compiler said nothing. ADR 0009 left open
whether the domains set the option.

ADR 0062 tested the option on the nine domains. The compiler gave 17
warnings. Each one was a relationship to one of the 15 list resources of an
organisation in `Rescord.Lists`, such as `Rescord.Lists.Species`. Those
resources had no `define` on the domain, so they were internal.

## Decision

- **Each domain sets `check [aliases: true]`** in its `boundary` block. A
  new domain sets it too.
- **Each of the 15 list resources of an organisation has a `define`**, which
  makes it public: `define :species_values, action: :read` for
  `Rescord.Lists.Species`, and the same name pattern for the others. A page
  still reads a list with `Rescord.Lists.values/2`, which gives the labels
  and the order.
- **A signal module is an export of the domain that emits it**
  (`exports [Rescord.Residents.Signals]`), when another domain listens. The
  domain that listens has the emitter in its `deps` (ADR 0067).

## Consequences

- The rule "a domain uses only what another domain exports" now holds for a
  relationship and for a signal listener, and not only for a call. A
  relationship to an internal resource of another domain, or to a resource
  of a domain that is not in `deps`, fails `mix precommit`.
- To use a resource of another domain in a relationship, give it a `define`
  on its domain. Do this only when the other domain should see the
  resource. Do not add an `exports` entry for a resource: the `define` is
  the door.
- `Rescord.Resource` writes a part of each resource, so a module of the
  core that it names there is an alias reference from each domain. The
  core exports such a module, as it does `Rescord.Resource.Checks` and
  `Rescord.Resource.VersionPolicies`.
- A `define` publishes the whole module of a list resource. Each domain
  named these modules in a relationship before, so nothing new is open.
- `boundary` knows only the modules that its tracer sees in the source. It
  does not know a module that a library makes with `Module.create`, such as
  the struct of a signal (`Rescord.Accounts.Signals.MemberInvited`) or a
  module `Ash.Signals.*`. It does not check a reference to such a module.
  `ash_boundary` exports each type that a public resource names in an
  attribute or an argument, so a public resource that names the struct of a
  signal as the type of an argument gives the warning "unknown module is
  listed as an export". ADR 0067 has the way around it.
- The open question of ADR 0009 and of `docs/architecture.md` is closed.
  Proposals B2 and B3 of ADR 0062 stay open.
