# AGENTS.md

The Mix project is `platform/`. Code paths in this file are relative to it
(`lib/rescord_web/widget.ex` means `platform/lib/rescord_web/widget.ex`), and
`mix` runs there. `docs/` and `devenv.nix` are at the repository root.

This file covers conventions and commands. It does not repeat the design.

## Read first

- `docs/domain.md` says what Rescord is for: the root entities, the scope,
  the design rules and the open points. It follows ASD-STE100 Simplified
  Technical English; keep it so when you change it.
- `docs/architecture.md` holds the decisions that shape the code, and is the
  source of truth. When the code and it disagree, fix one of them.
- `docs/adr/` records each decision, one file each. Write a new ADR
  (`NNNN-title.md`: status, context, decision, consequences, a few lines each)
  for any decision you make that neither place covers.
- `platform/AGENTS.md` holds the usage rules of the dependencies: some
  inline, and a link to the rest (ADR 0008). Read the rules of a package
  before you use it, and search its documentation with
  `mix usage_rules.search_docs`. Where a rule there differs from this file,
  this file wins. The examples there use Tailwind classes and `hero-` icon
  names, and they only discourage LiveComponents; none of that applies here.

## Commands

Run everything inside the devenv shell (`devenv shell`, or the `devenv hook`
auto-activation).

```sh
devenv up -d                      # PostgreSQL 18 in the background
cd platform
mix setup                         # deps, database (ash.setup), assets, seeds
mix test                          # sets up the test database first
iex -S mix phx.server             # http://localhost:4000
mix precommit                     # compile --warnings-as-errors, unlock unused deps, format, test
mix usage_rules.sync              # write platform/AGENTS.md again, after a change to the deps
```

Before every commit, run `mix precommit`, and also
`MIX_ENV=test mix compile --warnings-as-errors`, which compiles `test/support`
too.

## Conventions

- **No LiveComponents.** A page is built from LiveViews, function components,
  live widgets and nested LiveViews, in that order of preference
  (`docs/architecture.md`, "The parts of a page"). `RescordWeb` has no
  `live_component/0`. A part with no state is a function component. A part
  with state is a live widget, unless it needs a process of its own, and then
  it is a nested LiveView.
- **Pages are compositions of live widgets** (ADR 0003). A stateful part of a
  page is a widget in `lib/rescord_web/widgets/`, built as the `shoddy_phoenix`
  guide "Build a widget with lifecycle hooks" shows, with `RescordWeb.Widget`
  for the bookkeeping.
  - A widget module starts with `use RescordWeb, :widget` and
    `use ShoddyPhoenix.LiveView.Events, prefix: "<name>"`. Its state is a
    struct with a `:key`, its events are written with `event/1` and carry a
    `"widget"` parameter, and its `render/1` is a pure function component.
  - Each event clause checks the shape of its params and ends with a clause
    that ignores anything else. Find an instance with `Widget.fetch/3`, never
    with `String.to_atom/1` or `String.to_existing_atom/1`.
  - A page LiveView routes and lays out. It ends with a catch-all
    `handle_info/2` and a catch-all `handle_event/3` that ignore what no
    widget took.
- **HTML is semantic and CSS is classless** (ADR 0004). Use landmarks, headings
  in order, `<th scope>`, labels for every control, and ARIA where it adds
  meaning. The stylesheet styles elements, ARIA states and roles, and a few
  `data-` attributes. Never write a `class` attribute or a class selector.
  A variant that no element or ARIA state expresses is a `data-` attribute.
  - The stylesheet is one cascade layer per file, and a layer is a role
    (ADR 0007): `tokens`, `base`, `elements`, `layout`, `components`. Put a
    rule in the file of its layer under `assets/css/layers/`, never in
    `assets/css/app.css`, which only states the order of the layers and
    imports them. A new component is a section of `components.css`; add a
    layer only for a new role.
  - Icons are our own inline SVGs in `CoreComponents.icon/1`, always
    `aria-hidden`. There is no icon library.
  - The output of `phx.gen.*` and of the Ash generators has Tailwind classes
    and Heroicon names. Restyle it by hand before you commit it.
- **Boundaries** (ADR 0009). The `:boundary` compiler checks which module
  may use which, and a broken rule fails `mix precommit`.
  - A new domain uses `use Ash.Domain, extensions: [AshBoundary]`, and names
    what it uses in its `boundary` block, `deps [Rescord]` when a resource
    names `Rescord.Repo`. Then add the domain to the `deps` of `RescordWeb`
    in `lib/rescord_web.ex`.
  - The core, under `lib/rescord/`, uses no Phoenix and no `shoddy_phoenix`.
    The web layer uses no `Ash` module unless `RescordWeb` names that module
    in `deps`.
  - Do not silence a boundary warning by widening `deps` or `exports` until
    you know that the reference is right. Never add `use Boundary` to a
    domain: `AshBoundary` declares it.
- **Ash.**
  - Call a resource through the code interface on its domain
    (`define :open_alarms, action: :open` inside the domain's `resources`
    block), not with `Ash.read/2` from the web layer. The `define` is also
    what makes the resource public to the web layer.
  - Use an Ash signal when other resources should react to an action, in
    place of a call from an `after_action` hook, and AshWorkflow for a
    process of several steps, in place of a state machine and jobs written
    by hand (`docs/architecture.md`, "Signals and workflows"). A workflow is
    declared with `extensions: [AshWorkflow, AshOban]`, and its domain is
    in `ash_domains` in `config/config.exs`, or Oban gets no trigger from
    it (ADR 0010).
  - A widget that shows a resource reloads on that resource's
    `Ash.Notifier.PubSub` notification, on a topic named `<resources>:changed`.
  - Once there is authentication, every Ash call from a LiveView passes the
    actor explicitly. A refused read returns an empty result, not an error,
    so a test that reads asserts a non-empty result.
  - Each organisation has its own schema (ADR 0011). A resource that belongs
    to one organisation uses `multitenancy do strategy :context end`, and
    each call for it passes the tenant. Its migration goes in
    `priv/repo/tenant_migrations`.
  - History (ADR 0012). A fact that needs a history is a temporal resource,
    with `paper_trail do mode :temporal_inline end`. Any other resource that
    needs a trail uses AshPaperTrail in its default mode. A resource that a
    member can remove uses AshArchival. A resource with a workflow is never
    temporal. A change, validation or preparation for a temporal resource
    is a module that declares `temporal_safe?/1`; pass `as_of:` as an
    action option, and use `now()` in an expression, never the wall clock.
  - Policies and roles will be our own system in the manner of `ash_grant`
    (`docs/architecture.md`, "Policies and roles"). Do not add `ash_grant`
    as a dependency, and do not write a role into a policy by hand.
- **Browser code.** Write a browser-side hook in TypeScript. Parse what the
  server sends to it with zod when its shape matters; zod is not a dependency
  yet, so ask before the first use (`docs/architecture.md`, "Code in the
  browser").
- **Dependencies.** `shoddy` and `shoddy_phoenix` come from GitHub, pinned to a
  commit with `ref:` (ADR 0005). `shoddy_phoenix` is for the web layer only.
  Use them where they fit, and name any helper or workaround that could go
  back into them, in your reply and in the commit. Ask before you add any
  other dependency. After a change to the dependencies, run
  `mix usage_rules.sync` and commit `platform/AGENTS.md`; never edit that
  file between its `usage-rules` markers.
- **Tests.** A test that needs Postgres uses `Rescord.DataCase` or
  `RescordWeb.ConnCase`, which carry the `:postgres` tag. Any other test uses
  `ExUnit.Case` (ADR 0006).
- **Atoms.** Never create atoms from text that a client sends.
- **Branches.** Work is on `main` for now (the maintainer, 15 November 2026).
  Commit there and push `main`, with no pull request. A session whose own
  instructions name another branch still pushes `main`.

## Where things live

| Path | Contents |
| --- | --- |
| `platform/lib/rescord/` | domains and resources (Ash) |
| `platform/lib/rescord_web/live/` | page LiveViews |
| `platform/lib/rescord_web/widgets/` | live widgets: state, hooks, render |
| `platform/lib/rescord_web/widget.ex` | bookkeeping shared by widgets |
| `platform/lib/rescord_web/components/` | function components and layouts |
| `platform/assets/css/app.css` | the order of the CSS layers, and their imports |
| `platform/assets/css/layers/` | the classless stylesheet, one file per layer |
| `platform/AGENTS.md` | the usage rules of the dependencies, written by `mix usage_rules.sync` |
| `devenv.nix`, `devenv.yaml`, `devenv.lock` | the toolchain (ADR 0001) |
| `docs/architecture.md`, `docs/adr/` | the design and its decisions |
