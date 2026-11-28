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

**The repository is public, and a scan holds it clean** (ADR 0064).
`scripts/check-secrets.sh` runs Gitleaks over each commit, in CI for each
push and as a hook before a commit. Beside the rules of Gitleaks for
secrets, `.gitleaks.toml` has rules for what belongs to one deployment or to
one person: an email address that is not an example, the host name of an
app on a hosting service, and a `fly.toml`. The names of a deployment are in
no rule, because a rule is public. They come from a list of private terms
outside the repository: a file on the machine of a developer, and a secret
of the repository in CI.

## The toolchain

devenv provides Elixir 1.20.5 on Erlang/OTP 29, an elixir-ls built against
them, PostgreSQL 18, esbuild, and the driver of Playwright with the headless
shell of Chromium (ADR 0023), all from one pinned nixpkgs. PostgreSQL
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
| `Rescord.Mail` | the emails: a layout and a template for each one, in MJML | no other boundary; it may use `Phoenix.HTML`, which escapes each value |
| `Rescord.Application` | the supervision tree | the core and the web layer |

Each domain uses `extensions: [AshBoundary]`, which declares its boundary
from the domain. The web layer reaches data only through the code interface
of a domain.

Each domain checks alias references too (ADR 0066): a relationship and a
signal listener name a module, and the compiler checks that name as it
checks a call. A resource that another domain names in a relationship has a
`define` on its domain, which makes it public.

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

**Decompose each page, and use a widget only when it is needed** (ADR 0037).
A LiveView keeps the state and the events of its page, and its `render/1`
composes function components from a module of components for its area. A
part becomes a widget only when it needs state that the page does not need.

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
- **Rescord is mobile first** (ADR 0061). The phone is the first screen
  that a page is written for and looked at on, and `docs/mobile.md` holds the
  assessment.
  - No page is wider than a screen of 320px, and nothing scrolls sideways.
  - What a finger presses is 44px high or more (`--tap`), and the text of a
    control is 16px.
  - The site menu is a popover of HTML on a phone, with no script, and it is
    in the page on a wide screen.
  - A table is a list of cards on a phone: each cell says its column with
    `data-label`.
  - `RescordWeb.Features.PhoneTest` holds the rules in a browser with the
    screen of a phone.
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
- **A `<details>` keeps its state** when LiveView draws the page again
  (ADR 0031): `assets/js/details.ts` carries it over, and each `<details>`
  of a page has an id.
- **A hook may parse the data that the server sends with zod**, so that the
  shape of a `push_event` payload or of a `data-` attribute is checked where
  it enters the browser, and typed from there on. zod is not a dependency
  yet. It would be the first npm dependency, so the project then gets a
  `package.json` and a way to install it inside devenv.

### Browser tests

`RescordWeb.FeatureCase` drives a real Chromium against the real server, with
`PhoenixTest.Playwright` (ADR 0023). The first test signs a member in: the
form, the email, the link, the button, a page of an organisation, and the
sign-out.

- The driver and the browser come from nixpkgs, through `devenv.nix`. The
  project has no npm package. Outside the devenv shell, `mix test` leaves the
  browser tests out and says so.
- The tests run a server on port 4002, and build the assets first.
- In the tests only, a request and a LiveView of the browser use the database
  transaction of the test: the endpoint has the plug
  `Phoenix.Ecto.SQL.Sandbox`, and `RescordWeb.LiveSandbox` is the first hook
  of each live session.
- A request test holds each rule. A browser test holds what only a browser
  shows.

## Ash

The first domain is `Rescord.Accounts`: the users, the organisations and
their members (ADR 0022). For each domain:

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

A task uses AshStateMachine alone (ADR 0032): it has one step, which waits
for a person.

AshWorkflow is installed (ADR 0010), with `ash_state_machine`, `ash_oban` and
Oban. Oban starts in the supervision tree with the queues `default` and
`workflow`, and the generated triggers publish to `workflow`. A workflow is
declared on a resource with `extensions: [AshWorkflow, AshOban]`. There is no
workflow yet. Both ship usage rules, which `platform/AGENTS.md` links:
`deps/ash/usage-rules/signals.md` and `deps/ash_workflow/usage-rules.md`.

**A signal module is in the domain that emits it**, as
`Rescord.<Domain>.Signals`, and that domain exports it when another domain
listens (ADR 0067). There are two signals:

| Signal | Emitted by | Listeners |
| --- | --- | --- |
| `:resident_removed` of `Rescord.Residents.Signals` | `Resident.remove` | `Placement` finishes the placement, `TaskSubject` archives the subjects, and `Routine` takes the resident out. They run in the transaction of the removal. |
| `:member_invited` of `Rescord.Accounts.Signals` | the two invite actions of `Member` | `Member` sends the email in a job of Oban, which runs after the commit, and again after a fault of the mail server. |

A listener action has the line `authorize_if signal_in(Module, :signal)` in
its policy, because the person who acts often has no grant for it. ADR 0067
has the rules for a new signal. ADR 0062 assesses where more signals and
the first workflows fit.

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

**This is the first part of the domain, and it is built** (ADR 0018 to ADR
0022). `docs/domain.md`, section 5.1, has the rules:

- A person signs in with a link by email. Rescord stores no password.
- A person joins an organisation by invitation only.
- A root user creates each organisation and invites its administrators. An
  administrator invites the members, and can make another member an
  administrator. Root is a level of the user, outside each organisation.
- A root user can do anything in each organisation. No grant limits a root
  user (see "Policies and roles").
- The first root user comes from a script that a person runs in IEx when
  Rescord is first deployed.
- **The sign-in uses AshAuthentication** (ADR 0018), with its strategy for
  a link by email. The strategy makes no account for an address that it does
  not know.
- **A request for a sign-in link answers at once** (ADR 0019). Each way of
  the request runs in a supervised task: a known address, an address that
  Rescord does not know, and a fault. The answer is the same in each way, so
  neither its words nor its time say whether an address has an account.
- A member has one role of the organisation. Each organisation starts with
  an administrator and a member, and its administrators define more (see
  "Policies and roles").
- **An open page follows the user** (ADR 0036). A session names the sockets
  of its user, and `RescordWeb.UserAuth.disconnect/1` closes them after a
  sign-out, and after a change to the root grant or the role of the user.
  Each page then connects again with the user as the user is now.

- **The email goes through an SMTP server that the operator names**, with
  the SMTP adapter of Swoosh and `gen_smtp` (ADR 0044). Postmark is one such
  server, and a mail host of the refuge is another. The settings come from
  the environment at run time, and never from a file in the repository.
  `Rescord.Mailer.smtp_options/1` turns them into the options of the
  adapter, and with TLS the client checks the certificate of the server.
- **`Rescord.Mail` builds each email** (ADR 0070): the sign-in link, the
  invitation and the test email of `bin/check`. Each has an HTML part,
  written in MJML with EEx and compiled by the build, and a text part
  written by hand. The HTML part has the look of the application in a light
  and in a dark scheme, and loads no file of any host. The caller delivers
  the email with `Rescord.Mailer`.
- **A page names its organisation in the path** (the maintainer, 15
  November 2026), and not in a subdomain. One host and one certificate serve
  each organisation.

The path starts with `/o/` and then the short name of the organisation, for
example `/o/wattle-creek/residents` (the maintainer, 15 November 2026). The
fixed first part keeps the name of an organisation apart from a route such
as `/sign-in`.


### Lists and residents

`Rescord.Lists` and `Rescord.Residents` are the first domains of an
organisation, and their resources are the first temporal resources with a
table (ADR 0025).

- **A list.** Each dimension that an organisation can extend has a base
  list, which all organisations share, and a list in the schema of each
  organisation. A row of that list names a shared value, or it is a local
  value. A resident names a row of the list of its organisation.
- **A resident** holds what it has one of. Its name and its desex status are
  each a resource with one value, so each has a history. Its breeds, colours
  and temperaments are ties. `register` and `revise` take those as
  arguments, and one change writes them with the resident.
- **A group has words** that say how its members are related, such as
  `Sisters and an unrelated male` (ADR 0028). `Rescord.Residents.Kinship`
  calculates them from the parent links and the families. Rescord stores no
  other relation.
- **The housing is a tree** (ADR 0029). `Rescord.Locations` has a location,
  the tie that puts it inside another, and a placement of a resident or a
  group. A resident lives in its own placement, or with its group.
  `Rescord.Locations.tree/1` gives the page each location with who lives
  there and the count.
- **A member can say when a move happened.** `Rescord.Accounts.instant/2`
  turns the local time of a form into an instant that is not after now,
  and the write takes it as `as_of:`.
- **The journal** (ADR 0030). `Rescord.Journal` has the entry and the facts
  of each medical kind. The time that a thing happened is an attribute of
  the entry. The author and an administrator correct an entry, through a
  grant with the scope `own`.
- **A task** (ADR 0032) is due, done or skipped. It is not temporal, and it
  names a resident, a group or a location by a plain id. A task that names a
  prescription writes the dose to the journal when a member completes it.
  `Rescord.Tasks.day/2` gives the tasks of a day of the organisation.
- **A routine** (ADR 0033) is a task that repeats. It makes its tasks a
  number of days ahead: the setting `task_days_ahead` of the organisation,
  or the number of the routine. `Rescord.Tasks.Changes.SyncTasks` makes
  them when the routine starts or changes, and Oban runs
  `Rescord.Tasks.Workers.GenerateTasks` each hour for the later days.
  `generated_until` on the routine says up to which instant its tasks exist,
  so no task is made two times. `Rescord.Tasks.Pattern` gives the days of a
  pattern with no database and no clock.
- **The timeline** of a resident (ADR 0035) is its journal entries together
  with the changes that Rescord recorded. `Rescord.History` reads the
  versions of a temporal resource as changes, and each domain gives the
  changes of its own resources: `Rescord.Residents.changes/2` and
  `Rescord.Locations.changes/2`. `Rescord.Journal.timeline/2` puts them in
  one list.
- **The inventory** (ADR 0034) has items, lots, suppliers, stock movements
  and reorder levels. Rescord stores no level:
  `Rescord.Inventory.stock/1` adds the stock movements of each lot in each
  place. A movement out takes no more than the level, and a count writes
  the difference.
- **The status is a calculation** from the arrival, the departure and an
  absence, at the instant of the read. Rescord stores no status.
- **A read as of a past instant** takes `as_of:` in the options of a function
  of the domain.
- **Today is a date in the time zone of the organisation** (ADR 0026). The
  zone is a setting of the organisation, and the package `tz` has the rules.
  `Rescord.Accounts.today/1` and `local_date/2` give the date. Never use
  `Date.utc_today/0` for a rule or for a page of an organisation.
- **A tenant migration needs a repair.** ash_postgres 2.15.2 writes the
  period foreign key of a temporal resource with two faults.
  `Rescord.TenantMigrations.repair!/0` repairs them, and a test fails while
  a migration has one.

### Units of measure

`Rescord.Units` is a catalogue of units in the code, with the arithmetic on
quantities (ADR 0071). It is a plain module of the core: no table, no
dependency.

- **A unit** is `%Rescord.Units.Unit{}`: a unit of the catalogue, such as
  `kg`, or a ratio of two, such as `mg/kg`. `Rescord.Units.parse/1` reads a
  symbol, a name or a ratio. A ratio never cancels: `mg/kg` has the
  dimension `{:mass, :mass}`.
- **A quantity** is `%Rescord.Units.Quantity{value, unit}`, with a `Decimal`
  for its number. `convert/3`, `multiply/2`, `divide/2`, `add/2` and
  `subtract/2` check the units and return an error for units that do not
  fit. No function takes a float, and none rounds: a page rounds, with
  `Quantity.round/2`.
- **The list of units of an organisation says which units its forms
  offer**, and the name of a value is its meaning.
  `Rescord.Lists.known_unit/1` gives the unit of the catalogue for a value,
  or `:error` for a name such as `bag`, which Rescord does not convert.
  `Rescord.Journal.quantity/1` gives a measurement as a quantity.
- **Two Ash types**, `Rescord.Units.Types.Unit` and
  `Rescord.Units.Types.Quantity`, for an attribute and an argument. A
  quantity is a map in the database, with its number as text and the unit
  that the person wrote.
- **A page writes a quantity** with `RescordWeb.UnitWords.quantity/1`.

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
- **No actor reads a version through a policy** (ADR 0063). AshPaperTrail
  gives a version resource no authorizer, so `Rescord.Resource` gives each
  one a policy that refuses each actor. A domain reads the versions of its
  own resources, after the record that they belong to has decided.
- A fact that needs a history is a temporal resource in 6NF: the key, the
  period and one value (`docs/domain.md`, section 6).
- Temporal resources are experimental in Ash, and need PostgreSQL 18 and
  `btree_gist`, which the repo installs.
- A resource with a workflow cannot be temporal: AshStateMachine, AshOban and
  AshWorkflow declare no change as temporal safe. We tested this.
- A change, validation or preparation of ours that runs on a temporal
  resource declares `temporal_safe?/1`, and uses no `before_action` or
  `after_action` hook.

### Rate limits

**An action gets a rate limit from AshRateLimiter, and Hammer counts in
ETS** (ADR 0020). `Rescord.RateLimit` is the Hammer rate limiter, and the
application starts it. A resource names it as the backend in its
`rate_limit` section. The counts are in the memory of one node.

The first use is the request for a sign-in link: a limit for each address
on the action, inside the task of ADR 0019. The numbers are not decided.

The limit of a client counts the address of the client. Behind a reverse
proxy, `RescordWeb.ClientAddress` takes it from `X-Forwarded-For`, and
only when the connection comes from a proxy that the setting
`RESCORD_TRUSTED_PROXIES` names (ADR 0046).

### Files

**A file is in a store that is compatible with S3, and its record is in the
schema of the organisation** (ADR 0038, ADR 0041). `Rescord.Storage` is the
behaviour, and the configuration names the store: `Rescord.Storage.S3`,
with `req_s3`, for Garage in development and any service that is compatible
with S3 in production, and `Rescord.Storage.Disk`, a directory, in the tests
and by default in production (ADR 0044). A setting puts the bucket in the
path or in the host of each address (ADR 0045). Each key starts with the id of the
organisation, and no part of it comes from what a person sends. A person
reads a file through a controller that asks the policy, and the answer
names the type that Rescord found in the first bytes of the file.

A key gets its bytes one time, and no page deletes a file. So
`bin/move-storage` (`Rescord.Storage.Move`, ADR 0059) can copy the files
of one store into the other while the server works, for a server that
changes its store: it lists the old store, puts each file that the new
store does not have, reads it back, and compares it. It deletes nothing.

A photo goes through `Rescord.Images` before it reaches the store
(ADR 0055): libvips turns it as its EXIF says, writes it again with no
metadata, so no GPS position stays, and makes a thumbnail. A photo of the
journal and a photo of a resident get the same treatment. Only a few photos
go through libvips at the same time (ADR 0056): `Rescord.Images.Limit` has
two slots by default, a photo waits for a slot for 30 seconds at most, and
its work runs in a process of its own, so the memory of libvips is free
again when the slot is.

### Photos

**A resident has photos, each with a caption and a date, in albums, and one
of them is its profile picture** (ADR 0055). `Rescord.Photos` holds them, and
reads the photos of the journal of the resident as photos too: a photo of
the journal becomes a record of its own, which names the same files, when a
person puts it in an album or makes it the profile picture. The power
`residents` does the work, and `remove_residents` removes any photo.

### Transfers

**A partnership and a transfer are between two organisations, so they are
outside the schemas, with the organisations** (ADR 0042). Their policies
read the role of the actor in one of the two (`Rescord.Transfers.Checks.PowerIn`),
and their read is a filter of the organisations of the actor. A transfer
holds a copy of the resident as plain data, which the sender builds at the
transfer and which never changes.

A partner on another server gets a file (ADR 0043): an Ed25519 signature
over a header, and a payload encrypted for the receiver with X25519 and
AES-256-GCM, all with `:crypto` of OTP. The private keys of a refuge are in
the database, encrypted under `RESCORD_KEY_SECRET`. An import checks the
signature with the key of a recorded partner before it decrypts or
decompresses anything.

### Policies and roles

**Authorization is our own system, in the manner of `ash_grant`.** We write
it in this repository; `ash_grant` is the model and not a dependency.

A role is a record of the organisation (ADR 0040), with a list of powers.
A power is one area of work, and each domain says which grants each of its
powers gives. Each role also reads what the organisation has.
`Rescord.Accounts.Grants` turns a role into its grants, and holds the filter
of each scope. The policy of a resource of an organisation is the one check
`Rescord.Accounts.Checks.Granted`, after a bypass for a root user. Each
organisation starts with an administrator and a member, and its
administrators define more roles. A person gives only the powers that their
own role has.

What we take from the model (`ash_grant` 0.22):

- A role does not appear in a policy. A resolver turns an actor into a list
  of **grants**, and the policies of a resource are generated from, or check,
  those grants.
- A grant names a resource, an action and a **scope**. A scope is a named
  Ash `expr()` on the resource, such as `own` or `published`, so a grant
  becomes a native Ash policy check and a row filter.
- A refusal wins over a grant.

A root user is outside the grants: a root user can do anything in each
organisation (`docs/domain.md`, section 5.1). The conversations of the
assistant are the one exception (ADR 0069).

A domain other than the accounts holds its own grants, in a module that the
configuration names (ADR 0024): `reads/0` and `powers/0`. A domain that
is not in `:grant_sources` has no grants.

**What no grant gives, a policy refuses, and a test holds that for each
action** (ADR 0063). `Rescord.PolicySweepTest` asks the policies about each
action of each resource of each domain, as nobody, as a person of another
refuge, and as a member with each of three roles. An action that an actor
can run is a grant of the role of that actor, or it is in the short list of
the test of what is open on purpose, with its reason. A new resource or
action is thus closed until a person decides otherwise. A version resource
of the paper trail has a policy that refuses each actor: a domain reads the
versions itself, after the record that they belong to has decided.

Not decided yet: whether a grant can name one record or a group of fields. The rule above stays whatever the answer: a
refused read is empty and not an error, so a test that reads asserts a
non-empty result.

### Export

**An organisation exports its data as one ZIP of CSV files** (ADR 0054).
`Rescord.Export` reads each table as the person, with the power `export`,
as it stood at the end of a chosen day, and writes a README that says what
each file holds and which file each id names. Each resource of the domains
is in the export, or `Rescord.Export.excluded/0` says why not.

### What needs attention

**The first page of an organisation says what needs attention now**
(ADR 0065): the tasks that are overdue or due today, the stock to count
or to order, the residents that are late back or expected, the locations
over their capacity, and the transfers and partner requests that wait.
Each domain says what needs somebody in its part with a function
`attention`, and `Rescord.Attention.parts/2` asks each of them. Three
rules hold: a read runs as the person, so the policies decide what they
see; a row is there only for a role that can act on it; and a part has a
limit and a total. The page reads again each minute, because the time
alone makes a task overdue. A row is a link to the page of its record,
where the person acts.

### Settings

**The environment starts Rescord, and a resource holds each other
setting** (ADR 0068). A setting is in the environment only when Rescord
needs it before it can reach its database, before the first person can
sign in, or when it describes this machine. Each other setting is an Ash
resource with a page: of the server, in the shared schema, set by a root
user under `/root`; or of an organisation, in its schema, set by a member
with the power `settings`. A setting has one source, never both.

A secret of such a resource is encrypted with AshCloak in `Rescord.Vault`,
a plain module over `:crypto` whose key comes from `RESCORD_KEY_SECRET`.
A resource with a secret is not temporal, its paper trail leaves the
encrypted attribute out, and a page never shows the secret again. One
function of the domain decrypts it.

The settings of today move in releases of their own. The store of the
files is still in the environment.

### The assistant

**Ruby is an optional assistant that reads and drafts as the member**
(ADR 0069). It is built in phases, and a part of this section that the
code does not have yet is what its phase lands.

- The domain `Rescord.Ruby` holds the conversations, their messages and
  the proposals, in the schema of the organisation, and the code that
  calls `ash_ai`. The web layer calls its code interface.
- Each tool call passes the member as the actor and the organisation as
  the tenant. `Rescord.Ruby.Actor.for/1` is the one place that makes the
  actor, and it turns the root level off. No tool call passes
  `authorize?: false`.
- The loop of the model runs in a job of Oban, and cannot write.
  `Rescord.Ruby.Gate` turns a write into a proposal, and
  `Rescord.Ruby.confirm_proposal/2` runs it in the request of the member,
  through the action of the domain that the form uses.
- A tool is a line of `Rescord.Ruby.Catalogue`. A read that is a function
  of a domain is a digest in `Rescord.Ruby.Digests`. A tool names each
  record with a reference, and the page makes each link and each card
  from the references, never from the words of the model.
- A provider is a row of `Rescord.Ruby.Provider`, and the use of one
  organisation is a row of `Rescord.Ruby.Settings`. Each request goes
  through `Rescord.Ruby.LLM.Client`, which counts its tokens.
- **The resources of the conversations have no bypass for a root user.**
  A conversation is read by its member and by the administrators of its
  organisation. It is deleted for real: not temporal, no paper trail, no
  archive. Both are exceptions that ADR 0069 states.
- No test calls a provider: a scripted model answers.

## Releases

**A rescue runs Rescord on a server of its own** (ADR 0044). One `mix
release` goes out as a Docker image with a Compose file, a Nix package with
a NixOS module, and a tarball with a systemd unit. `Rescord.Release`
migrates the database and each schema of an organisation, and makes the
first root user, with no Mix. Each package migrates before each start.
The settings that start Rescord come from the environment, and
`docs/self-hosting.md` lists them. Each other setting is a resource
(ADR 0068). `GET /health` says whether the database answers.

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

- The open points of `docs/domain.md`, and so the domains and the pages
  that come after the residents.
- The design of the grants: see "Policies and roles".
- The proposals of ADR 0062 that wait for the maintainer: what the
  departure of a resident ends, the operation id of a version, and the
  first workflow.
- How a cloud session (which runs as root, where devenv's PostgreSQL cannot
  start) gets a toolchain and a database. CI runs in devenv (ADR 0047).
- The gaps in the accessibility of Cinder that ADR 0017 leaves: the choice
  filter and the pages.
- Whether a hook that a component writes next to its markup
  (`Phoenix.LiveView.ColocatedHook`) can be TypeScript, or whether every hook
  is a file under `assets/js/`. Nobody has checked.
