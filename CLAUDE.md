# CLAUDE.md

The Mix project is `platform/`. Code paths in this file are relative to it
(`lib/rescord_web/widget.ex` means `platform/lib/rescord_web/widget.ex`), and
`mix` runs there. `docs/` and `devenv.nix` are at the repository root.

This file covers conventions and commands. It does not repeat the design.

## Read first

- `docs/architecture.md` holds the decisions that shape the code, and is the
  source of truth. When the code and it disagree, fix one of them.
- `docs/adr/` records each decision, one file each. Write a new ADR
  (`NNNN-title.md`: status, context, decision, consequences, a few lines each)
  for any decision you make that neither place covers.

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
```

Before every commit, run `mix precommit`, and also
`MIX_ENV=test mix compile --warnings-as-errors`, which compiles `test/support`
too.

## Conventions

- **Pages are compositions of live widgets** (ADR 0003). A stateful part of a
  page is a widget in `lib/rescord_web/widgets/`, built as the `shoddy_phoenix`
  guide "Build a widget with lifecycle hooks" shows, with `RescordWeb.Widget`
  for the bookkeeping. There are no LiveComponents, and `RescordWeb` has no
  `live_component/0`.
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
  meaning. `assets/css/app.css` styles elements, ARIA states and roles, and a
  few `data-` attributes. Never write a `class` attribute or a class selector.
  A variant that no element or ARIA state expresses is a `data-` attribute.
  - Icons are our own inline SVGs in `CoreComponents.icon/1`, always
    `aria-hidden`. There is no icon library.
  - The output of `phx.gen.*` and of the Ash generators has Tailwind classes
    and Heroicon names. Restyle it by hand before you commit it.
- **Ash.**
  - Call a resource through the code interface on its domain
    (`define :open_alarms, action: :open` inside the domain's `resources`
    block), not with `Ash.read/2` from the web layer.
  - A widget that shows a resource reloads on that resource's
    `Ash.Notifier.PubSub` notification, on a topic named `<resources>:changed`.
  - Once there is authentication, every Ash call from a LiveView passes the
    actor explicitly. A refused read returns an empty result, not an error,
    so a test that reads asserts a non-empty result.
- **Dependencies.** `shoddy` and `shoddy_phoenix` come from GitHub, pinned to a
  commit with `ref:` (ADR 0005). `shoddy_phoenix` is for the web layer only.
  Ask before you add any other dependency.
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
| `platform/assets/css/app.css` | the classless stylesheet |
| `devenv.nix`, `devenv.yaml`, `devenv.lock` | the toolchain (ADR 0001) |
| `docs/architecture.md`, `docs/adr/` | the design and its decisions |
