# ADR 0009: The compiler checks the boundaries, with boundary and ash_boundary

Status: accepted (asked for by the maintainer)

## Context

Two of our rules had only a reviewer to hold them: the web layer calls a
resource through the code interface of its domain and never through `Ash`,
and `shoddy_phoenix` is for the web layer only. A rule that only a reviewer
holds is broken sooner or later.

`boundary` is a compiler that checks the references between groups of
modules. `ash_boundary` is an extension for an `Ash.Domain` that writes the
`boundary` declaration of the domain from its DSL.

## Decision

- `ash_boundary` is a dependency, and `:boundary` is the first compiler of
  the project. `ash_boundary` 0.2.0 asks for `boundary ~> 0.10.4`.
- There are three boundaries that we write by hand:
  - `Rescord`, the core: the modules under `Rescord` that are not a domain.
    It exports `Rescord.Repo`. It may not reference `:phoenix`,
    `:phoenix_live_view`, `:phoenix_html` or `:shoddy_phoenix`, nor the web
    layer. `Phoenix.PubSub` is the application `:phoenix_pubsub`, which it may
    use.
  - `RescordWeb`, the web layer. It may use the exports of the core and of
    each domain that its `deps` names. It may not reference `:ash`: a module
    of Ash that it needs, such as an error struct, is named in `deps`.
    `:ash_phoenix` is a separate application, which it may use.
  - `Rescord.Application`, which starts both, and so depends on both.
- Each Ash domain uses `extensions: [AshBoundary]`, and is a boundary of its
  own, a sibling of the three above. A resource with a `define` on the
  domain is public. Every other module of the domain is internal. A domain
  names the boundaries that it uses in the `deps` of its `boundary` block,
  the core among them when its resources name `Rescord.Repo`.
- The web layer and the core check alias references too
  (`check: [aliases: true]`), so naming a module is checked as well as
  calling it.
- The two test case modules are boundaries that nothing checks
  (`check: [in: false, out: false]`), which is what `boundary` advises for
  test support.

## Consequences

- A broken rule is a compiler warning, and `mix precommit` compiles with
  `--warnings-as-errors`, so it fails the gate.
- We tried each rule with a domain that we then removed. Each of these
  failed the compile: the web layer calling a domain that is not in its
  `deps`, calling `Ash.read!/1`, and naming a resource with no `define`; the
  core naming `Phoenix.Component`, `ShoddyPhoenix.LiveView` and
  `RescordWeb.Endpoint`. The web layer calling the code interface of a
  domain in its `deps` compiled, and so did the core calling
  `Phoenix.PubSub`.
- A relationship from a resource to a resource of another domain is an
  alias reference. `ash_boundary` does not check it unless the domain sets
  `check [aliases: true]`. We have not decided whether domains set it.
- An `Ash.Notifier.PubSub` is often given the endpoint as its module. The
  core cannot name the endpoint, so a domain publishes through a module of
  the core that wraps `Phoenix.PubSub`.
- `ash_boundary` is young: version 0.2.0, with about 700 downloads. It pins
  an older `boundary` than the newest, 0.12.0. Both compiled and checked
  correctly on Elixir 1.20.5.
- With `clarity` installed, each domain gets a diagram of its dependencies.
  `clarity` is not a dependency.
