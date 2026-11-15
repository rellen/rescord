# Rescord architecture

This document records the decisions that shape the code. Each decision has
an ADR in `docs/adr/` with its reasons, unless the maintainer gave it here
directly. What Rescord does is not decided yet, so this document covers the
platform that it will be built on.

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

## Boundaries

**The compiler checks which module may use which** (ADR 0009), with
`boundary` and `ash_boundary`. A broken rule is a warning, and the gate
compiles with warnings as errors.

| Boundary | Holds | May use |
| --- | --- | --- |
| `Rescord` | the core: the repo, the mailer, plain modules | no Phoenix, no `shoddy_phoenix`, not the web layer |
| each Ash domain | its resources; those with a `define` on the domain are public | the boundaries in the `deps` of its `boundary` block |
| `RescordWeb` | the web layer | the core's exports, and the public part of each domain in its `deps`; not `Ash` itself |
| `Rescord.Application` | the supervision tree | the core and the web layer |

Each domain uses `extensions: [AshBoundary]`, which declares its boundary
from the domain. The web layer reaches data only through the code interface
of a domain.

## The web layer

### The parts of a page

**We avoid LiveComponents.** A page is built from these four parts, and
`RescordWeb` has no `live_component/0`:

| Part | Use it for |
| --- | --- |
| LiveView | a page. It owns the route and the layout, and composes the other parts. |
| Function component | markup with no state of its own. This is the default for any part of a page. |
| Live widget | a stateful part of a page that lives in the page's process (ADR 0003): its state is a struct in the page's assigns, its events and messages reach it through lifecycle hooks, and it renders with a function component. |
| Nested LiveView | a stateful part that needs a process of its own: one that must not take the page down when it crashes, or that outlives a part of the page. It costs a process, and it shares no assigns with the page. |

Reach for them in that order. A part with no state is a function component.
A part with state is a live widget, unless it needs its own process, and then
it is a nested LiveView (`live_render/3`). A widget with no `:handle_params`
hook also works inside a nested LiveView.

### Markup and CSS

- **The markup is semantic and the CSS is classless** (ADR 0004). The
  stylesheet styles elements, ARIA states and roles, and a few `data-`
  attributes, in a light and a dark scheme that follow the system. There is
  no Tailwind, daisyUI or icon library.
- **The stylesheet is one cascade layer per file, and a layer is a role**
  (ADR 0007). `assets/css/app.css` states the order of the layers and imports
  one file per layer from `assets/css/layers/`: `tokens`, `base`, `elements`,
  `layout`, `components`, and then `colocated` for the CSS that a component
  writes next to its markup. A later layer wins over an earlier one whatever
  the specificity; inside a layer, specificity and order decide as usual.
  esbuild bundles the files with `app.js`.
- `CoreComponents` keeps the API of the components that `mix phx.new`
  generates, so generated code still calls them, but renders classless
  markup.

### Code in the browser

- **Browser-side hooks are written in TypeScript.** esbuild bundles
  TypeScript with no other tool, but it only removes the types: a type check
  needs `tsc`, which is not set up yet. There is no hook yet:
  `assets/js/app.js` is the generator's file, and it becomes TypeScript when
  the first hook arrives.
- **A hook may parse the data that the server sends with zod**, so that the
  shape of a `push_event` payload or of a `data-` attribute is checked where
  it enters the browser, and typed from there on. zod is not a dependency
  yet. It would be the first npm dependency, so the project then gets a
  `package.json` and a way to install it inside devenv.

## Ash

There is no domain yet. When there is one:

- each domain uses `AshBoundary`, and the web layer calls resources through
  the code interfaces on their domain (see "Boundaries");
- changes reach the pages through `Ash.Notifier.PubSub` notifications, which
  the widgets that show a resource subscribe to;
- once there is authentication, every Ash call from a LiveView passes the
  actor explicitly.

### Signals and workflows

**We use Ash signals and AshWorkflow where they fit**, before we write the
same thing by hand.

- **Ash signals** are part of Ash. A signal module declares typed signals, an
  action emits one with `emit`, and another resource listens with
  `signals_in`. Use a signal when other resources should react to an action
  and the resource that acts should not know them, in place of a call from an
  `after_action` hook. The emitter gets nothing back, so call a code
  interface when the action needs an answer. A signal is not for PubSub:
  what a page hears after a commit is still a notifier's work.
- **AshWorkflow** declares a process of several steps on a resource: steps
  that run in the background, steps that wait for a person, deadlines and
  reminders. It generates the states and transitions of `ash_state_machine`
  and the triggers of `ash_oban`. Use it for such a process, in place of a
  state machine and jobs written by hand.

AshWorkflow is not a dependency yet. It brings `ash_state_machine`,
`ash_oban` and so Oban, which needs a queue and a place in the supervision
tree. Install it with `mix igniter.install ash_workflow` when the first
workflow arrives. Both ship usage rules: `deps/ash/usage-rules/signals.md`,
and those of `ash_workflow` once it is installed.

A signal module that two domains share has to be in a boundary that both
can use. Where that module lives is not decided.

### Policies and roles

**Authorization will be our own system, in the manner of `ash_grant`.** We
write it in this repository; `ash_grant` is the model and not a dependency.

What we take from the model (`ash_grant` 0.22):

- A role does not appear in a policy. A resolver turns an actor into a list
  of **grants**, and the policies of a resource are generated from, or check,
  those grants.
- A grant names a resource, an action and a **scope**. A scope is a named
  Ash `expr()` on the resource, such as `own` or `published`, so a grant
  becomes a native Ash policy check and a row filter.
- A refusal wins over a grant.

Not decided yet, and each is a decision for an ADR when the work starts:
how a grant is written (`ash_grant` uses a string,
`resource:instance:action:scope`), where roles and their grants are stored,
whether a grant can name one record or a group of fields, and how the system
is tested without a database. The rule above stays whatever the answer: a
refused read is empty and not an error, so a test that reads asserts a
non-empty result.

## Libraries

**We use `shoddy` and `shoddy_phoenix`, and we look for ways to give
patterns back to them.** They are the maintainer's libraries: `shoddy` has
helpers for results, options and collections, and `shoddy_phoenix` has the
LiveView helpers, the plumbing of the live widgets among them. Both come
from GitHub, pinned to a commit (ADR 0005).

- Use a function of theirs where it says the same thing in fewer words.
- When Rescord writes a helper that is not about Rescord, such as
  `RescordWeb.Widget`'s bookkeeping, or works around a gap in a library, that
  is a candidate for the library. Say so in the reply or the commit that
  adds it, so that the maintainer can move it upstream, and then replace
  the local copy with the library's.

## Guidance for agents

- `AGENTS.md`, at the repository root, holds Rescord's conventions. It is
  written by hand, and it wins over any other guidance.
- `platform/AGENTS.md` holds the usage rules that the dependencies ship.
  `mix usage_rules.sync` writes it from the `usage_rules` key of
  `platform/mix.exs`: the rules of `usage_rules` itself, of Elixir and of OTP
  inline, and a link to the rules of each other dependency. Run the task
  after a change to the dependencies (ADR 0008).

## Open questions

- What Rescord does, and so its domains and pages.
- Authentication, and how actors reach Ash from LiveViews.
- The design of the grants: see "Policies and roles".
- Whether a domain checks its relationships into other domains
  (`check [aliases: true]`), and where a signal module that two domains
  share lives (ADR 0009, "Signals and workflows").
- CI, and how a cloud session (which runs as root, where devenv's PostgreSQL
  cannot start) gets a toolchain and a database.
- Whether to keep the Swoosh mailer that the generator added.
- Whether a hook that a component writes next to its markup
  (`Phoenix.LiveView.ColocatedHook`) can be TypeScript, or whether every hook
  is a file under `assets/js/`. Nobody has checked.
