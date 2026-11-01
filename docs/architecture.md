# Rescord architecture

This document records the decisions that shape the code. Each decision has
an ADR in `docs/adr/` with its reasons. What Rescord does is not decided yet,
so this document covers the platform that it will be built on.

## The repository

| Path | Contents |
| --- | --- |
| `platform/` | the Phoenix and Ash application, OTP app `:rescord` (ADR 0002) |
| `devenv.nix`, `devenv.yaml`, `devenv.lock` | the toolchain and PostgreSQL (ADR 0001) |
| `docs/` | this document and the ADRs |

The repository root holds no `mix.exs`. Mix runs in `platform/`.

## The toolchain

devenv provides Elixir 1.20.5 on Erlang/OTP 29, an elixir-ls built against
them, PostgreSQL 18, and esbuild, all from one pinned nixpkgs. PostgreSQL
runs as a devenv process on `127.0.0.1:5432` with a `postgres`/`postgres`
superuser, which is the login that Phoenix's generated config uses. The
config reads `PGHOST` and `PGPORT`, which devenv sets. See ADR 0001.

## The web layer

- **Pages are compositions of live widgets** (ADR 0003). A widget is a
  stateful part of a page that lives in the page's LiveView process: its state
  is a struct in the page's assigns, its events and messages reach it through
  lifecycle hooks, and it renders with a pure function component. A page
  LiveView only routes and lays out. There are no LiveComponents.
- **The markup is semantic and the CSS is classless** (ADR 0004). One
  stylesheet, `assets/css/app.css`, styles elements, ARIA states and roles,
  and a few `data-` attributes, in a light and a dark scheme that follow the
  system. esbuild bundles it with `app.js`. There is no Tailwind, daisyUI or
  icon library.
- `CoreComponents` keeps the API of the components that `mix phx.new`
  generates, so generated code still calls them, but renders classless
  markup.

## Ash

There is no domain yet. When there is one:

- the web layer calls resources through the code interfaces on their domain;
- changes reach the pages through `Ash.Notifier.PubSub` notifications, which
  the widgets that show a resource subscribe to;
- once there is authentication, every Ash call from a LiveView passes the
  actor explicitly.

## Libraries

`shoddy` (helpers for results, options and collections) and `shoddy_phoenix`
(LiveView helpers, the widget plumbing among them) come from GitHub, pinned
to a commit (ADR 0005).

## Open questions

- What Rescord does, and so its domains and pages.
- Authentication, and how actors reach Ash from LiveViews.
- CI, and how a cloud session (which runs as root, where devenv's PostgreSQL
  cannot start) gets a toolchain and a database.
- Whether to keep the Swoosh mailer that the generator added.
