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
- A collection that is the page keeps its search, its filters, its sort
  and its page in the address, with `Cinder.UrlSync` (ADR 0084): the
  residents, the members, the organisations, the items of the inventory,
  the journal of a resident (in the list layout, ADR 0092). A collection
  that is a part of a page does not: the stock history of an item.
- Cinder is for a collection that needs a filter, a sort or pages. A
  short list stays a table by hand (ADR 0079).
- The markup of Cinder has gaps in accessibility, which ADR 0014 lists. We
  work around the first one (ADR 0017): `assets/js/cinder_tables.ts` makes
  the sort of a table column a button for the keyboard, and gives the header
  cell `aria-sort`. The same module closes the others (ADR 0087): the
  state and the name of a choice filter and its arrow keys, the pages as
  a landmark, the names of the buttons and of a table, and a status
  region that says the new count of a result.

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
    screen of a phone, on the pages that `RescordWeb.PagesFixtures` names.
- **Each page keeps WCAG 2.2 AA, and a browser test holds it** (ADR 0090).
  - `RescordWeb.Features.AccessibilityTest` runs axe-core on each page of
    `RescordWeb.PagesFixtures`, on a phone and on a wide screen, in both
    schemes. It also holds the landmarks, the headings, the titles, the
    text spacing of WCAG 1.4.12 and the focus of the keyboard. The package
    `a11y_audit` carries axe-core, for the tests only.
  - `Layouts.app` writes the skip link, the site header, `main` and the
    site footer, which links to the colophon at `/colophon` and to its
    accessibility statement. `Layouts.plain` is the same with no menu,
    and an error page uses it.
  - Each page has a title of its own, with " · Rescord" after it.
  - The name of a control starts with the words that show on it.
- **A developer sees each core component by itself in the catalogue**
  (ADR 0095): the page `/dev/components`, which development and the tests
  have. An example is a template of its own, which the page renders and
  shows as text. The phone test and the accessibility test visit the
  page, so each example is held to the rules of a page. There is no
  Phoenix Storybook.
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
- **A button copies the address of a calendar feed** (ADR 0074):
  `assets/js/copy.ts` listens for a press on a button with `data-copy`,
  which names a field. Without the script the field still works.
- **The focus of the keyboard keeps its place** (ADR 0090):
  `assets/js/focus.ts` puts it back in the row of a button that a render
  took away, by the `id` of the row, and on the `h1` of a new live page.
- **The loading bar is CSS** (ADR 0090): `app.js` sets `data-loading` on
  the root element while LiveView loads, and `layout.css` draws the bar.
  There is no topbar script.
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

**Lines that actions of one resource share go in a pipeline** (ADR 0086),
when the group has three lines or more, or three actions or more take it.
Ash puts the lines of the pipeline in each action at compile time, so the
action is the same as one with the lines written in it. A pipeline keeps
the order of the lines: it runs each change before each validation, and a
group with another order stays in its actions. `Rescord.Expenses.Expense`
has the first two.

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
listens (ADR 0067). There are three signals:

| Signal | Emitted by | Listeners |
| --- | --- | --- |
| `:resident_removed` of `Rescord.Residents.Signals` | `Resident.remove` | `Placement` finishes the placement, `TaskSubject` archives the subjects and skips a due task that has none left, and `Routine` takes the resident out. They run in the transaction of the removal. |
| `:resident_departed` of `Rescord.Residents.Signals` | `Departure.record` | The same three resources: the placement ends, the resident goes out of each routine and of each task that is due, and a due task that has no subject left is skipped. A task that is done keeps the resident. A withdrawal restores nothing. |
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
  grant with the scope `own`. The journal page reads the entries in
  pages, with `Rescord.Journal.query_to_journal/2` (ADR 0092), and an
  event of the page finds an entry again with
  `Rescord.Journal.entry_of/3`.
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
  the difference. The calculation `stock` of an item gives the same for
  the items of one read, so a page of the inventory reads the movements
  of the items that it shows (ADR 0088).
- **The status is a calculation** from the arrival, the departure and an
  absence, at the instant of the read. Rescord stores no status.
- **A read as of a past instant** takes `as_of:` in the options of a function
  of the domain.
- **Today is a date in the time zone of the organisation** (ADR 0026). The
  zone is a setting of the organisation, and the package `tz` has the rules.
  `Rescord.Accounts.today/1` and `local_date/2` give the date. Never use
  `Date.utc_today/0` for a rule or for a page of an organisation.
- **A date, a time of day and a number have the forms of the locale of
  the organisation** (ADR 0075). The locale is a setting of the
  organisation, a tag such as `en-AU` from the list of
  `Rescord.Accounts.locales/0`, and the package `localize` has the forms,
  with the file of each locale in `priv/localize/locales`.
  `RescordWeb.Locale` is the one module that calls it: a page calls
  `ResidentWords.date/1`, `TaskWords.day/1`, `TaskWords.time/1`,
  `JournalWords.time/1` and `JournalWords.number/1`. Never use
  `Calendar.strftime/2` or `to_string/1` for a date or a number that a
  person reads. An export keeps ISO dates and plain numbers.
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

### Measurements and charts

**The measurements of a resident over time are series, and a chart is SVG
that the server writes** (ADR 0080). There is no chart library and no
script of ours.

- **A measure kind can name its standard unit** (ADR 0094), which an
  administrator sets on the page Lists. A person may record another unit
  that `Rescord.Units` converts to it, and the measurement keeps the
  number and the unit that the person recorded: nothing is stored in a
  converted form. A new measurement of such a kind needs the standard
  unit or a unit that converts to it: `Rescord.Lists.units_for/2` and
  `accepted_units/2` hold the rule for the journal and for the forms. A
  measurement from before stays as it is.
- **A read gives a measurement in the standard unit**:
  `Rescord.Journal.standard/1` gives `%Rescord.Journal.Standard{}`, with
  the value in the standard unit of the kind and what was recorded, and
  rounds nothing. `RescordWeb.MeasurementWords.measurement/1` writes it
  for a page: "610 g (recorded as 0.61 kg)". The export has the
  calculations `standard_value` and `standard_unit` of a measurement
  beside `value` and `unit_id`.
- **A series** is `%Rescord.Journal.Series{}`: the measurements of one
  kind for one resident, in the order of time, in one unit, which is the
  standard unit of the kind, or the unit of the newest measurement for a
  kind with none. A measurement in another unit is a point
  when `Rescord.Units` converts it, and is in `others` when it does not.
  Each point has its change from the point before.
  `Rescord.Journal.series/2` gives the series of a resident and
  `series_of/2` those of several, with the read action of the journal, as
  the person.
- **`RescordWeb.Chart` is the geometry**, with `Decimal` and no word:
  round ticks, the place of a point as a percentage, the band of a point,
  the path of a line.
- **`RescordWeb.ChartComponents`** has `line_chart/1` and `sparkline/1`.
  The `<svg>` has no `viewBox` and each place is a percentage, so a dot
  and a word keep their size at each width. Only the line is in a nested
  `<svg>` that stretches. The numbers of the axis and the two dates are
  HTML. The look is the section "charts" of `components.css`, from the
  tokens.
- **A chart is one image**, with a name, and the caption of its figure as
  its description. Its values are a table in the same card, and no part of
  the chart takes the keyboard focus. A press on a point is the LiveView
  event `pick`.
- **The pages** are `RescordWeb.MeasurementsLive` (a resident: a card for
  each kind, a time range in the address, and a form that writes a journal
  entry) and `RescordWeb.GroupMeasurementsLive` (a group: one kind for
  each member, as small charts on one scale). The page of a resident has a
  sparkline beside each newest value. `RescordWeb.MeasurementWords` writes
  a value, a change and the caption of a chart.

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

Rescord writes a record before it puts the file, in one transaction, so a
fault after the put leaves a file that no record names. `bin/check-files`
(`Rescord.Storage.Compare`, ADR 0091) finds those leftovers and says how
much space they take, and it finds a file that a record names and the
store lost. It lists the store with the size of each file
(`Rescord.Storage.files/0`), and each domain that keeps files gives the
keys of its records with `file_keys/1`, read from each row of the table
with no actor (`Rescord.Storage.Named`). It changes nothing.

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

### Reports

**A report is a PDF that an action writes** (ADR 0076). Each of the eight
reports is a generic action of `Rescord.Reports.Report`, a resource with
no table, and returns an `AshTypst.Document`. `Rescord.Reports.Render`
runs it in three steps. A module below `Rescord.Reports.Facts` reads the
records through the other domains as the person, and never with
`authorize?: false`. The module that the configuration names
(`:report_wording`, which is `RescordWeb.ReportWords`) turns the facts
into text, because the words are in the web layer. Then Typst renders the
template of `priv/typst`, which gets the text as one value, `d`, and the
photos as virtual files. No text of a record is markup of Typst. Each role
can make each report, and a person makes 30 in a minute at most.
`RescordWeb.ReportController` sends a report for a `GET`.

**A report is on A4 or on US Letter** (ADR 0093). The paper is the
attribute `paper_size` of the organisation, A4 at first, which an
administrator changes on the settings page. Each report action takes the
optional argument `paper` for one document on the other paper, and each
address of a report takes `paper`. The render puts the paper into the
frame of the document, and `report` of `look.typ` sets the page from it:
a template has one layout for both papers.

### Expenses

**An organisation records its expenses, and Rescord is not its accounting
system** (ADR 0082). `Rescord.Expenses` has two resources in the schema of
each organisation: `Expense`, with a state machine and a paper trail, and
`Receipt`, a file of an expense that `Rescord.Storage.Upload` checks as it
checks an attachment of the journal. An amount is an
`AshMoney.Types.Money`, which PostgreSQL stores as the composite type
`money_with_currency` of the schema `public`. A new expense is in the
currency of its organisation, an attribute that an administrator sets, and
no action takes a currency. Rescord converts no amount, so a sum is a list
with one amount for each currency (`Rescord.Expenses.sum/1`). An expense
can hold the tax that is in its amount (ADR 0089): money in the currency
of the amount, which `Changes.SetTax` makes from a number, only while the
organisation names a tax in its attribute `tax_name`. Rescord knows no
rate. A member reads their own expenses, and the power `manage_expenses`
reads and decides each one. `RescordWeb.Locale.money/1` writes an amount for a
person. The list of the page goes out as a CSV file
(`RescordWeb.ExpenseFileController`), with the filters of the address.

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

### Calendar feeds

**A member subscribes to a calendar feed in their calendar app**
(ADR 0074): the tasks, the days on which residents are expected back, and
the expiry dates of the stock, as iCalendar text at
`/o/<short name>/calendar.ics`. Rescord publishes and the app reads:
nothing in a calendar changes a record. Each domain says what its dated
things are with a function `calendar`, and `Rescord.Calendars.entries/4`
asks each of them. Four rules hold. The address is the key: it holds a
token, Rescord stores only the hash, and the page shows the address one
time. A feed reads as the member who made it, so the policies decide what
it holds, and it reads only while that member could make it. An event
holds the least that is useful: no name of a member, and the words that a
person wrote only when the member asks for them. And each refusal gets
the same answer. A feed needs the power `calendar`, and a person with the
power `members` sees and revokes the feed of each member.

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

The secret of the server can change. A value of the vault starts with the
id of its key, so a server with `RESCORD_KEY_SECRET_PREVIOUS` reads the
values of both secrets and writes with the new one. `bin/rotate-vault`
then writes each value of the old secret again: the secrets of the
settings (`Rescord.Vault.rotate/0`) and the private keys of the transfers
(`Rescord.Transfers.rewrap_keys/0`). `bin/check` counts what still needs
the old secret.

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
- `Rescord.Ruby.say/3` saves the message of a member and starts the job
  of its reply, in the queue `ruby`, which runs five replies at a time: a
  busy hour of Ruby cannot fill the other queues. The job is the trigger
  `respond` of AshOban on `Rescord.Ruby.Message`. It holds the id of the
  message, the organisation and the id of the member, and no word of the
  message. It runs the tool loop as that member
  (`Rescord.Ruby.Changes.Respond`), saves the reply as it arrives, and
  ends it with a state and, when it failed, a reason of
  `Rescord.Ruby.Reason`. A job runs one time, because the provider bills
  each try. No page waits for it: the reply is written also when the
  member has closed the page.
- Each reply adds its tokens and their price to `Rescord.Ruby.Usage`:
  one row for a member, a day and a model, with no word of a
  conversation, which stays when the conversation is deleted.
  `Rescord.Ruby.Allowance` sums a month of the calendar, in UTC, against
  the allowance of the settings, and `say` refuses a message past it.
  `say` also refuses a conversation that is full, from the size of the
  prompt that the provider reported, and more than 6 messages of one
  person in a minute or 120 in a day (ADR 0020). The check is before a
  reply and the price is known after, so the spend limit at the provider
  is the backstop.
- The system prompt is one text for the whole server
  (`Rescord.Ruby.Prompt`). What differs is in the header of the first
  message of a member: the rescue, the role, the day and the time zone.
  The header is stored with the message and sent again as it was, so the
  start of a conversation never changes and the provider can cache it.
- A tool is a line of `Rescord.Ruby.Catalogue`. A read that is a function
  of a domain is a digest in `Rescord.Ruby.Digests`. A tool names each
  record with a reference, and the page makes each link and each card
  from the references, never from the words of the model.
- A provider is a row of `Rescord.Ruby.Provider`, and the use of one
  organisation is a row of `Rescord.Ruby.Settings`. Each request goes
  through `Rescord.Ruby.LLM.Client`, which counts its tokens.
- The settings keep the place that a person of the organisation agreed
  to, as a short key and as the sentence that the page showed. Ruby is on
  for an organisation only while the provider is offered and its place
  has that key: `Rescord.Ruby.status/1` says where Ruby stands, and
  `Rescord.Ruby.available?/2` whether a person can ask. A root user who
  changes the place of a provider writes no row of an organisation: the
  two keys differ, and that is what stops Ruby.
- **The resources of the conversations have no bypass for a root user.**
  A conversation is read by its member and by the administrators of its
  organisation. It is deleted for real: not temporal, no paper trail, no
  archive. Both are exceptions that ADR 0069 states.
- No test calls a provider: a scripted model answers.
- The evaluation set measures what a real model does with the tools and
  the prompt. `mix rescord.ruby.eval` plants a rescue of made-up records
  (`Rescord.Ruby.Eval.Seed`), asks each question of
  `Rescord.Ruby.Eval.Cases` three times with the options of a reply, and
  scores each answer by code (`Rescord.Ruby.Eval.Score`): the tools that
  were called, each reference and each number against the tool results,
  patterns for what the answer must and must not say, and its form. A
  case passes when each run passes, and each group has a bar: 95% of the
  reads, and each case of the groups where Ruby must say that the records
  hold nothing, must not advise on the care of an animal, and must not
  follow an instruction inside a record. Only a person runs it, because
  it costs money and its result can change. The checks see words and not
  meaning, so a person reads the answers that failed.

## The log, the metrics and the errors

**The log says whose a line is, and holds nothing of a person** (ADR 0077).

- `Rescord.Log.context/1` sets the fields of a line for the process:
  the id of the user and of the organisation, which a request and a page
  set, and the id, the worker, the queue and the try of a job. The
  formatter writes them with `request_id`.
- A line holds no name, no address, no text of a person, no token and no
  file, and never the message of an error: the message of an Ash error
  holds the value that Ash refused. `Rescord.Log.reason/1` gives the safe
  text of a failure, which is the class and the modules of a Splode error
  with the fields that are atoms. `Rescord.LogRulesTest` fails for a call
  of `Logger` that uses `inspect` or a function of `Exception`.
- `Rescord.Log.Translator` stands in front of the translator of Elixir. A
  process that stops with a fault writes the shape of its last message,
  and not the message, which for a page is the form of the person.
- `Rescord.Log.Jobs` writes a line for a job of Oban that fails. Oban
  writes none, and its own logger writes the arguments of the job.
- The operator sets the level with `RESCORD_LOG_LEVEL`. The format is
  text.

**The metrics are for the operator, and are off until the operator names a
port** (ADR 0077). `RescordWeb.Telemetry.metrics/0` is the list, as
`Telemetry.Metrics` definitions: the requests and the pages there, and the
queries, the actions of Ash, the jobs, the emails, the photos and the VM
in `Rescord.Metrics`. With `RESCORD_METRICS_PORT`, a reporter (Peep) keeps
the numbers, and a web server of its own answers `GET /metrics` in the
format of Prometheus. No tag holds a value that a client sends or the id
of a person. A number about the work of a rescue is on a page (see "What
needs attention"), and not a metric. Rescord does not use AshMetrics, and
has no traces.

**An error of our own is a Splode error in a class of Ash** (ADR 0077).
Each action answers with the classes of Ash, and Rescord has no second
tree. A new failure that can reach a person is a module with
`use Splode.Error` and the class `:invalid` or `:forbidden`, in the domain
that returns it, and not a sentence: Ash reads a sentence as a fault of
the code. An atom is for a result that only the caller sees. The sentences
that some functions still return change with the localisation.

## Releases

**A rescue runs Rescord on a server of its own** (ADR 0044). One `mix
release` goes out as a Docker image with a Compose file, a Nix package with
a NixOS module, and a tarball with a systemd unit. `Rescord.Release`
migrates the database and each schema of an organisation, and makes the
first root user, with no Mix. Each package migrates before each start.
So a rescue that we do not know runs each migration on its own data:
`docs/migrations.md` holds the rules of a migration, and each one has a
line in the upgrade notes of its release, which a check holds (ADR 0073).
Before a start changes anything, it rehearses the upgrade: each pending
migration, of the database and of each organisation, in one transaction
that is taken back (`Rescord.Release.Rehearsal`, ADR 0081). A migration
that fails there stops the start, and the old version still runs.
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
- The proposals of ADR 0062 that wait for the maintainer: the operation id
  of a version, and the first workflow.
- How a cloud session (which runs as root, where devenv's PostgreSQL cannot
  start) gets a toolchain and a database. CI runs in devenv (ADR 0047).
- Nobody has listened to a collection with a screen reader. ADR 0087
  closed the gaps of the markup of Cinder that a browser can show.
- Nobody has used any page with a screen reader, and nobody has checked
  Safari or Firefox. ADR 0090 says what the automated test does not see.
- Whether a hook that a component writes next to its markup
  (`Phoenix.LiveView.ColocatedHook`) can be TypeScript, or whether every hook
  is a file under `assets/js/`. Nobody has checked.
