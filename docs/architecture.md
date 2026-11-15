# Rescord architecture

Rescord is a management system for an animal rescue or an animal refuge.
`docs/domain.md` describes the domain: the root entities, the scope, the
design rules and an estimate of the resources for each organisation.

This document records the decisions that shape the code. Each decision has
an ADR in `docs/adr/` with its reasons, unless the maintainer gave it here
directly. It covers the platform; no part of the domain is built yet.

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

### Collections

**A collection of records is shown with Cinder** (ADR 0014): a table, a list
or a grid, with filters, a sort, a search and pages, built from an Ash query.
We do not write those by hand.

- A page passes `query={...}`, which the code interface of a domain builds
  (`query_to_<name>/2`) with the tenant and, for a past date, `as_of`. It
  also passes the actor and the tenant to `Cinder.collection`. So the web
  layer uses no `Ash` module.
- Cinder renders through a LiveComponent of its own. That is its business:
  we still write none.
- `RescordWeb.CinderTheme` is the theme of each collection, and it has
  almost no class. The layer `vendor` of the stylesheet styles the parts of
  Cinder by their `data-key` attribute.
- A widget that shows a collection tells Cinder to load again with
  `Cinder.Refresh.refresh_table/2`, when the notification of the resource
  arrives.
- The markup of Cinder has gaps in accessibility, which ADR 0014 lists. We
  work around the first one (ADR 0017): `assets/js/cinder_tables.ts` makes
  the sort of a table column a button for the keyboard, and gives the header
  cell `aria-sort`. The other gaps stay for now.

### Markup and CSS

- **The markup is semantic and the CSS is classless** (ADR 0004). The
  stylesheet styles elements, ARIA states and roles, and a few `data-`
  attributes, in a light and a dark scheme that follow the system. There is
  no Tailwind, daisyUI or icon library.
- **The look is the design direction Scrubs** (ADR 0015): surgical green
  leads, on a soft mint ground, with round corners and the typeface
  Atkinson Hyperlegible, which the application serves itself.
  - A colour has one meaning: green is well and done, red is what needs
    somebody now, and blue is information, a link and the keyboard focus.
  - A state is a shape and a word, never the colour alone:
    `<.state kind="ok">In care</.state>`.
  - There are three grounds: the page (`bg`), a card on it (`surface`), and
    a menu above a card (`raised`).
  - Only `tokens.css` writes a colour, and `RescordWeb.TokensTest` holds each
    pair of a colour and its ground to WCAG AA in both schemes.
- **The stylesheet is one cascade layer per file, and a layer is a role**
  (ADR 0007). `assets/css/app.css` states the order of the layers and imports
  one file per layer from `assets/css/layers/`: `tokens`, `base`, `elements`,
  `layout`, `components`, `vendor`, and then `colocated` for the CSS that a
  component writes next to its markup. A later layer wins over an earlier one whatever
  the specificity; inside a layer, specificity and order decide as usual.
  esbuild bundles the files with `app.js`.
- **The layer `vendor` is the one exception to classless** (ADR 0014). It
  styles the markup that a dependency renders, which today is Cinder. That
  markup has classes that we did not write, and `vendor.css` may select such
  a class, below the root element of the dependency. No other file selects a
  class, and our own markup has none.
- `CoreComponents` keeps the API of the components that `mix phx.new`
  generates, so generated code still calls them, but renders classless
  markup.

### Code in the browser

- **Browser-side hooks are written in TypeScript.** esbuild bundles
  TypeScript with no other tool, but it only removes the types: a type check
  needs `tsc`, which is not set up yet. The first module is
  `assets/js/cinder_tables.ts` (ADR 0017). `assets/js/app.js` is still the
  generator's file, and it imports the module.
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

AshWorkflow is installed (ADR 0010), with `ash_state_machine`, `ash_oban` and
Oban. Oban starts in the supervision tree with the queues `default` and
`workflow`, and the generated triggers publish to `workflow`. A workflow is
declared on a resource with `extensions: [AshWorkflow, AshOban]`. There is no
workflow yet. Both ship usage rules, which `platform/AGENTS.md` links:
`deps/ash/usage-rules/signals.md` and `deps/ash_workflow/usage-rules.md`.

A signal module that two domains share has to be in a boundary that both
can use. Where that module lives is not decided.

### Tenancy

**Each organisation has its own schema of PostgreSQL** (ADR 0011). An
organisation is a rescue or a refuge, and it is one tenant. A resource that
belongs to one organisation uses the `:context` strategy of Ash. The
organisations, the users and the tokens of a sign-in are shared, outside
those schemas. A member, inside the schema of an organisation, connects a
user to it. The maintainer expects tens of organisations.

The first resource in the schema of an organisation needs
`Rescord.Repo.all_tenants/0`, which lists the schemas. Without it
`mix ash.setup` stops, and so does `mix test`.

### Sign-in and organisations

**This is the first part of the domain that we build** (the maintainer,
15 November 2026). `docs/domain.md`, section 5.1, has the rules:

- A person signs in with a link by email. Rescord stores no password.
- A person joins an organisation by invitation only.
- A root user creates each organisation and invites its administrators. An
  administrator invites the members, and can make another member an
  administrator. Root is a level of the user, outside each organisation.
- A root user can read the data of each organisation.
- The first root user comes from a script that a person runs in IEx when
  Rescord is first deployed.
- **The sign-in uses AshAuthentication** (ADR 0018), with its strategy for
  a link by email. The strategy makes no account for an address that it does
  not know.
- A member is an administrator or a member. The grants can hold more roles
  later (see "Policies and roles").

- **The email goes through Postmark, with the SMTP adapter of Swoosh** (the
  maintainer, 15 November 2026). The adapter needs the package `gen_smtp`.
  Postmark takes SMTP at `smtp.postmarkapp.com` on port 587 with STARTTLS.
  The name and the password are the API token of the Postmark server, or the
  two keys of an SMTP token. They come from the environment at run time, and
  never from a file in the repository.
- **A page names its organisation in the path** (the maintainer, 15
  November 2026), and not in a subdomain. One host and one certificate serve
  each organisation.

The mailer is not set up for production yet. `config/config.exs` names the
local adapter of Swoosh for each environment, and `config/prod.exs` stops its
store, so a release sends no email today.

The path starts with `/o/` and then the short name of the organisation, for
example `/o/wattle-creek/residents` (the maintainer, 15 November 2026). The
fixed first part keeps the name of an organisation apart from a route such
as `/sign-in`.


### History

**History comes from temporal resources, AshPaperTrail and AshArchival**
(ADR 0012).

| Question | Tool |
| --- | --- |
| What was true on a past date? | A temporal resource keeps each version of a record with its period, and a read or a write happens as of one instant. |
| Who changed a record, and how? | AshPaperTrail. On a temporal resource it stamps each version row (`mode :temporal_inline`); on any other resource it writes to a version resource. |
| What did a removed record hold? | AshArchival turns a destroy into a mark on the row. |

- **Each resource uses `Rescord.Resource`** in place of `Ash.Resource`
  (ADR 0013). By default a resource is temporal, keeps a paper trail,
  archives on a destroy, and is in the schema of an organisation. The
  compiler refuses a resource that is temporal and has a workflow.
- A fact that needs a history is a temporal resource in 6NF: the key, the
  period and one value (`docs/domain.md`, section 6).
- Temporal resources are experimental in Ash, and need PostgreSQL 18 and
  `btree_gist`, which the repo installs.
- A resource with a workflow cannot be temporal: AshStateMachine, AshOban and
  AshWorkflow declare no change as temporal safe. We tested this.
- A change, validation or preparation of ours that runs on a temporal
  resource declares `temporal_safe?/1`, and uses no `before_action` or
  `after_action` hook.

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

- The open points of `docs/domain.md`, and so the domains and the pages.
- For the sign-in: how actors reach Ash from LiveViews, and how a root user,
  who is not a member, reads the schema of an organisation.
- The design of the grants: see "Policies and roles".
- Whether a domain checks its relationships into other domains
  (`check [aliases: true]`), and where a signal module that two domains
  share lives (ADR 0009, "Signals and workflows").
- CI, and how a cloud session (which runs as root, where devenv's PostgreSQL
  cannot start) gets a toolchain and a database.
- The gaps in the accessibility of Cinder that ADR 0017 leaves: the choice
  filter and the pages.
- Whether a hook that a component writes next to its markup
  (`Phoenix.LiveView.ColocatedHook`) can be TypeScript, or whether every hook
  is a file under `assets/js/`. Nobody has checked.
