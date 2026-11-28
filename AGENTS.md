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
- `docs/migrations.md` says how to write a migration for a rescue that we
  do not know, and what each release tells an operator about its
  migrations. Read it before you change the database.
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
mix test                          # sets up the test database, builds the assets, runs a server on port 4002
iex -S mix phx.server             # http://localhost:4000
mix precommit                     # compile --warnings-as-errors, unlock unused deps, format, test
mix test.mutation --files lib/rescord/units  # mutation testing with muex, a report only (ADR 0104)
mix usage_rules.sync              # write platform/AGENTS.md again, after a change to the deps
```

The packages of a release (ADR 0044), from the root of the repository:

```sh
docker build -t rescord:local platform     # the image
nix build .#rescord                        # the Nix package
nix flake check                            # the package and a NixOS test of the module
scripts/release-tarball.sh amd64 arm64     # the tarballs in dist/, with Docker buildx
scripts/upgrade-test.sh OLD_IMAGE NEW_IMAGE  # an upgrade with its data, as the release runs it (ADR 0051)
scripts/check-upgrade-notes.sh             # each new migration has its upgrade note (ADR 0073)
```

After a change to `platform/mix.lock`, set the hash of `fetchMixDeps` in
`nix/package.nix` again: `nix build` prints the new one. When the version
of `mdex_native` changes there, set `mdexNative` in the same file too: its
version, and the two hashes of its native library. The same holds for
`mjml` and `mjmlNative` (ADR 0070).

CI runs the checks of each push in the devenv shell (`.github/workflows/ci.yml`,
ADR 0047), in jobs side by side from one compile (ADR 0103): the checks of
the code, the tests in parts (`mix test --partitions`), the browser tests in
parts of their own, the checks of the workflows and the scripts, and the
flake check (`nix.yml`). The job `CI` gives one result for the run. A push to
`main` cancels the run of the push before it. When `main` has waited an hour
for a result, `.github/workflows/ci-catch-up.yml` starts a run that no push
cancels (ADR 0078, `scripts/ci-catch-up.sh`). To get a result for `main` now,
start the workflow `CI` on `main` from the Actions page or the API: no push
cancels that run either.

Mutation testing (ADR 0104) is not part of CI. `mix test.mutation` runs
muex on the files that `--files` names, or on the lines that changed since
a ref (`--since v0.2.0`). A run of muex skips the set-up of `mix test`,
so set up first: `MIX_ENV=test mix do ash.setup --quiet + assets.build`.
A mutant that survives is a lead for a test, not a fault.
`.github/workflows/mutation.yml` runs it each Monday on the lines that
changed since the last release, and by hand from the Actions page.

Before every commit, run `mix precommit`, and also
`MIX_ENV=test mix compile --warnings-as-errors`, which compiles `test/support`
too.

## Nothing confidential, and nothing of one deployment

This repository is public (ADR 0064). It never holds a secret, a token, a
password, the address or the name of a real person, or what belongs to one
deployment: its host name, its `fly.toml`, the name of its database. Such a
thing belongs in the environment of a server, or in the private repository
of that deployment. An example uses `example.org` and a refuge that does
not exist, such as Wattle Creek.

- `scripts/check-secrets.sh` scans the history with Gitleaks and the rules
  of `.gitleaks.toml`. CI runs it for each push. A commit on `main` cannot
  be changed, so CI is too late for a secret: run the script **before each
  push**. The devenv shell installs it as the hook `pre-commit`, which scans
  what the commit holds. Outside the shell:
  `nix shell --inputs-from . nixpkgs#gitleaks -c scripts/check-secrets.sh`.
- The names of a deployment cannot be in the rules, which are public. Give
  them to the script as a list of private terms: the file that
  `RESCORD_PRIVATE_TERMS` names, or `.private-terms` at the root, which Git
  ignores. In CI the list is the secret `PRIVATE_TERMS` of the repository.
- A finding that is no secret takes an allowlist in `.gitleaks.toml`, with
  its reason, as narrow as it can be. A comment `gitleaks:allow` does
  nothing. After a change to the rules, run
  `scripts/check-secrets.sh --self-test`, and give a new rule a sample
  there.

## Commits, the changelog and releases

ADR 0060 holds the rules, and says what a major, a minor and a patch mean
for Rescord.

- **The message of a commit follows Conventional Commits**:
  `type(scope)!: subject`. The type is `feat`, `fix`, `perf`, `refactor`,
  `docs`, `test`, `build`, `ci`, `chore` or `revert`, and the scope is
  optional. `fix(security)` marks a security fix. A `!`, or a footer
  `BREAKING CHANGE:`, marks a change after which an upgrade needs a step by
  hand, or that breaks a setting, a command or a format that an operator or
  a partner server relies on. The types give the size of the next release,
  so `feat` is only for what a user or an operator gets. A commit on `main`
  cannot be changed: `scripts/check-commit-message.sh` checks a message, as
  the hook `commit-msg` that the devenv shell installs, and as a job of CI
  for the commits after the release 0.2.0. Write each message so now.
- **A commit that an operator or a user can notice adds its entry to
  `CHANGELOG.md`**, in the same commit, under `## [Unreleased]`: in Added,
  Changed, Deprecated, Removed, Fixed or Security, and in "Upgrade notes",
  the first section, for what an operator must do or know at the upgrade.
  An entry is full sentences for a person who runs a server. It is not the
  subject of the commit. A commit with a migration always adds a line to
  "Upgrade notes": see "Migrations and upgrades".
- **Release only when the maintainer asks.** On the newest commit of
  `main`, run `scripts/release.sh`. It finds the new version from the
  commits since the last tag, writes it in `platform/mix.exs`, which is its
  one home (the Nix package reads it there), gives the section "Unreleased"
  its version and its date, and commits `chore(release): X.Y.Z`. It stops
  when a new migration has no upgrade note. Before you run it, read the
  upgrade notes as `docs/migrations.md`, "Before a release", says. Push the
  commit to `main`. Then run the workflow Release on `main` from the Actions
  page, which makes the tag such as `v0.2.0`, or push that tag.
  `release.yml` runs the checks of CI, the flake check and the test of an
  upgrade, and publishes the image, the tarballs and the GitHub release.
- A rescue installs a release, and `docs/self-hosting.md` names the newest
  one: `scripts/release.sh` writes the new version there and in
  `deploy/compose/env.example`.
- After a change to a workflow, such as a new version of an action, run
  Release with `dry_run`: it builds and checks each part, and publishes
  nothing.

## Migrations and upgrades

Rescord is open source, and a rescue that we do not know runs each
migration at the first start of a new version, on its own data, with no
developer near, and goes back only with a backup. `docs/migrations.md`
holds the rules in full, with the form of an upgrade note and of a step by
hand (ADR 0073). Read it before you write a migration. In short:

- **Each migration has a line in `CHANGELOG.md`, in the same commit**,
  under `### Upgrade notes` of `## [Unreleased]`, in the list of the entry
  "**Migrations.**". The line holds the name of the file with no `.exs`,
  where it runs ("in the database" or "in each organisation"), what it
  does for a person who runs a server, and what it does to the rows that
  are there ("It changes no row", or which rows and by which rule).
  `scripts/check-upgrade-notes.sh` fails for a migration with no line: run
  it before each push that adds a migration. CI runs it for each push, and
  `scripts/release.sh` before a release.
- **A start rehearses the upgrade before it changes anything**
  (ADR 0081): `bin/migrate` runs each pending migration, of the database
  and of each organisation, in one transaction that it takes back, and
  migrates only when each one passed. So no migration sets
  `@disable_ddl_transaction` or `@disable_migration_lock`, builds an
  index `CONCURRENTLY`, or uses what PostgreSQL gives only after a
  commit, such as a new value of an enum type. Try yours with
  `mix run --no-start -e "Rescord.Release.rehearse()"`.
- **A migration of a release never changes**: no edit, no new name, no
  removal. Put a fault right with a new migration.
- **Read what `mix ash.codegen` wrote, in both directories**, as the
  operator of a rescue with years of rows. A removal of a column, a new
  name, and a new rule on a table with rows each need a decision.
- **A migration runs by itself, and calls no code of Rescord**: only
  `Ecto.Migration` and SQL in `execute/1`. No resource, no function of a
  domain, no setting, no network. It works on empty tables and on many
  rows, and it stays in its transaction.
- **A new rule states what happens to an old row that breaks it**:
  `null: false`, a unique index, a check, a foreign key, an exclusion. In
  this order: the migration puts the rows right by a rule that loses
  nothing; or the upgrade keeps the rows and Rescord asks a member in the
  pages (ADR 0065); or, as the last choice, a step by hand. A migration
  never fails on the rows of a rescue with only the error of PostgreSQL.
- **A data migration is a file of its own**, in SQL, with a `WHERE` that
  leaves out each row that is right already. It does not guess a value.
  A table of a temporal resource has a row for each version: say in the
  `@moduledoc` and in the upgrade note what the migration does to the
  history.
- **A step by hand is a breaking change** (`!`), and its steps are in the
  upgrade notes in full, under "**Before the upgrade.**" or "**After the
  upgrade.**": why, a query that finds the rows in each organisation, how
  to put each right, how to know that the step is done, and what happens
  without it. The migration checks first, and stops with a message and a
  hint that name the step, and that hold no value of a row: the rehearsal
  prints them for each organisation, before anything changes.
- **Say what goes and what takes long.** The note of a migration that
  removes a column, a table or rows says what a rescue loses. The note of
  a migration that writes a large table again says that the first start
  takes longer.
- **A migration that changes or checks rows is tried on rows**: on a
  database for development with records, `up`, `down` and `up` again; and
  in `scripts/upgrade-test.sh`, with rows of that kind that the last
  release makes.

## Conventions

- **No LiveComponents.** A page is built from LiveViews, function components,
  live widgets and nested LiveViews, in that order of preference
  (`docs/architecture.md`, "The parts of a page"). `RescordWeb` has no
  `live_component/0`. A part with no state is a function component. A part
  with state is a live widget, unless it needs a process of its own, and then
  it is a nested LiveView.
- **Decompose each page** (ADR 0037). A LiveView keeps the route, the state,
  the events and the layout, and its `render/1` composes parts from modules
  of their own. A part is a function component by default, in
  `lib/rescord_web/components/<area>_components.ex`, with an `attr` for each
  value that it shows. A LiveView past about 250 lines still holds a part.
- **A live widget only when it is needed** (ADR 0037, which changes
  ADR 0003): a part with state of its own that the page does not need,
  such as a stateful part that two pages share. Then it is a widget in
  `lib/rescord_web/widgets/`, built as the `shoddy_phoenix` guide "Build a
  widget with lifecycle hooks" shows, with `RescordWeb.Widget` for the
  bookkeeping.
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
    (ADR 0007): `tokens`, `base`, `elements`, `layout`, `components`, `vendor`.
    Put a rule in the file of its layer under `assets/css/layers/`, never in
    `assets/css/app.css`, which only states the order of the layers and
    imports them. A new component is a section of `components.css`; add a
    layer only for a new role.
  - Icons are our own inline SVGs in `RescordWeb.Icons`, always
    `aria-hidden`, drawn on a grid of 24 with one round line of 2 units
    (ADR 0102). There is no icon library. An icon is never alone: words
    beside it say what it means. One place of the site has one shape
    (`Icons.section/1`), and one shape has one meaning. No icon on a
    "Save", on Cancel, or on the button of a form whose `summary` has it.
  - The icon of a tab is the mark of the site bar, drawn again in
    `priv/static/images/favicon.svg` (ADR 0058). After a change to it, run
    `scripts/favicons.sh` from the root of the repository, which writes
    `favicon.ico` and `apple-touch-icon.png` again.
  - The look is the design direction Scrubs (ADR 0015). Only
    `assets/css/layers/tokens.css` writes a colour: read a token in every
    other layer. A colour has one meaning: `ok` (green) is well and done,
    `alert` (red) is what needs somebody now, `info` (blue) is information.
    The grounds are `bg` for the page, `surface` for a card and `raised` for
    a menu above a card. An `article` is a card.
  - A state is a shape and a word, never the colour alone. Write
    `<.state kind="ok">In care</.state>`, with the kind `ok`, `alert`,
    `info` or `none`.
  - A new pair of a colour and its ground takes a line in
    `RescordWeb.TokensTest`, which holds each pair to WCAG AA in both
    schemes.
  - The typeface is Atkinson Hyperlegible, served from
    `priv/static/fonts`. Do not load a font, a script or a stylesheet from
    another host.
  - The layer `vendor` is the one exception (ADR 0014). It styles the markup
    that a dependency renders, which has classes that we did not write, and
    it may select such a class below the root element of the dependency.
    Our own markup still has no class, inside a slot of Cinder too.
  - The output of `phx.gen.*` and of the Ash generators has Tailwind classes
    and Heroicon names. Restyle it by hand before you commit it.
- **Mobile first** (ADR 0061, `docs/mobile.md`). Write a page for a phone,
  and look at it with a width of 360px and of 320px, in both schemes, before
  a wide screen.
  - A CSS rule with no media query is the rule of a phone. A query adds
    what a wider screen has room for. Nothing scrolls sideways.
  - What a finger presses is as high as `--tap` (44px): a button, a field, a
    summary, the label of a box, a link of a menu. The elements layer does
    this, so do not make a control smaller in a component.
  - A table is a list of cards on a phone. Give each `<td>` but the first
    `data-label="<its column>"`. In a cell that Cinder writes, put the label
    on a `<span data-label="…">` around the value. A cell of buttons and a
    state need no label.
  - A list of things with a button each is a `<ul>` with the button as a
    child of the `<li>`: the stylesheet makes rows of it.
  - Pass `section` to `Layouts.app`, so that the site menu marks the part
    that the page is in.
  - Prefer HTML and CSS to a script: `popover`, `<details>`, `:has()`.
  - Wrap a `:hover` rule in `@media (hover: hover)`.
  - `RescordWeb.Features.PhoneTest` visits each kind of page with the
    screen of a phone. Add a new page to `RescordWeb.PagesFixtures`, which
    names the pages for it.
- **Each page keeps WCAG 2.2 AA** (ADR 0090). The markup rules above do
  most of it. These are the rest:
  - `RescordWeb.Features.AccessibilityTest` runs axe-core on each page of
    `RescordWeb.PagesFixtures`, in a browser. A new page goes there, and a
    new kind of control still needs a person who uses it with the
    keyboard.
  - A page has one `main`, one `h1`, and no level of heading skipped.
    `Layouts.app` writes the skip link, the site header and the site
    footer. A page with no menu, such as an error, uses `Layouts.plain`.
  - Each page has a title of its own: assign `page_title` in a LiveView,
    and pass it to `render` in a controller. The root layout adds
    " · Rescord".
  - The name of a control starts with the words that show on it. Write
    `aria-label={"Take off #{receipt.name}"}` on a button that says "Take
    off", never "Take invoice.pdf off": a person who speaks to the device
    says the words that show (WCAG 2.5.3).
  - A link or a button that shows only a picture, a sign or a file type
    has an `aria-label`.
  - A row, a card or a list item that holds a button has an `id` that
    stays the same from one render to the next. `assets/js/focus.ts` puts
    the focus of the keyboard back in that place when the button goes,
    and on the `h1` of a new live page. Do not move the focus yourself.
  - Nothing moves for a person who asks for less motion: the base layer
    stops each animation and transition of CSS. Do not animate with a
    script.
  - A change to what a page can or cannot do for a person with a
    disability changes the accessibility statement of the colophon
    (`controllers/page_html/colophon.html.heex`) too.
- **The catalogue of the components** (ADR 0095) is the page
  `/dev/components`, in development and in the tests. A new function of
  `CoreComponents`, a new state of one, and a new icon get an example: a
  template in `lib/rescord_web/controllers/catalogue_html/examples/` and
  a line of the list in `RescordWeb.CatalogueHTML`. The headings of an
  example start at `h4`, and each `id` in it starts with `example-`. The
  phone test and the accessibility test hold each example as they hold a
  page. Do not add Phoenix Storybook.
- **A collection of records is a `Cinder.collection`** (ADR 0014): a table,
  a list or a grid with filters, a sort, a search and pages. Do not write
  those by hand.
  - Pass `query={...}` from the code interface of the domain
    (`Rescord.Residents.query_to_residents(%{}, tenant: tenant)`, with
    `as_of:` for a past date), never `resource={...}`. Pass `actor` and
    `tenant` too.
  - Do not pass `theme`, and do not pass `class` to a slot. The theme is
    `RescordWeb.CinderTheme`, from the configuration, and the look is in
    `assets/css/layers/vendor.css`, which selects the `data-key` of a part.
  - **A collection that is the page keeps its state in the address**
    (ADR 0084): the LiveView has `use Cinder.UrlSync` after
    `use RescordWeb, :live_view`, and the collection gets
    `url_state={@url_state}`. One collection of a page takes it, because
    the parameters have no prefix. A collection that is a part of a page,
    such as the stock history of an item, does not. The page reads none of
    those parameters itself.
  - Give a collection an `<:empty :let={found}>` slot with two sentences:
    one for `found.filtered?`, and one for a collection with nothing yet.
  - What a row shows is a load of the query, or a thing that the page reads
    once for the organisation: the page does not see the rows of Cinder.
    Give the loads in the option `query` (`query: [load: [...]]`): the
    option `load` of a `query_to_` function does nothing to the query.
    A field that Elixir calculates takes no sort and no filter of Cinder.
    For a search on one, the domain narrows the query, as
    `Rescord.Accounts.members_with_email/2` does. For a filter on one, a
    `<:filter>` slot takes a function in `fn`, and the domain narrows
    the query, as `Rescord.Inventory.with_fault/3` does (ADR 0088). Make
    that function once, in `mount`, and find the value of the address
    in a fixed list: never make an atom from it.
  - When the query needs a filter that the web layer cannot write, the
    domain has a function that returns the query, as
    `Rescord.Inventory.query_to_history/2` does.
  - A short list with no filter, no sort and no pages stays a table by
    hand (ADR 0079).
  - Cinder has a LiveComponent inside. That does not change "No
    LiveComponents":
    we write none.
  - After a change to the version of Cinder, run `RescordWeb.CinderTest` and
    look at a collection in a browser. The test fails for a class of Cinder
    that `vendor.css` does not know.
  - Change the version of Cinder by hand in `mix.exs`. Do not run
    `mix igniter.install cinder`, which sets Tailwind up, or
    `mix cinder.upgrade`, which edits the Tailwind configuration.
  - `assets/js/cinder_tables.ts` makes the sort of a table column work from
    the keyboard (ADR 0017). It reads the markup of Cinder, and
    `RescordWeb.CinderTest` holds the two together. Do not take the two
    `dom` callbacks out of `assets/js/app.js`: without them a sort control
    loses the focus.
  - The same module names the controls of a collection for a screen reader
    and keeps the list of a choice filter open under the arrow keys
    (ADR 0087). Do not take `watchCinderLists()` or `holdCinderListsOpen()`
    out of `app.js`. It names a table by the heading of its
    `section[aria-labelledby]`, or by the `h1` of the page: put a
    collection that is a part of a page in such a section.
    `RescordWeb.Features.CollectionsTest` holds this in a browser.
- **An email is MJML, with a text part** (ADR 0070). `Rescord.Mail` builds
  each email, and the caller delivers it with `Rescord.Mailer`.
  - A new email is a template `lib/rescord/mail/<name>.mjml.eex` with the
    content of the card, a module beside it with `text/1`, a function in
    `Rescord.Mail`, and an entry in `previews/0`. `Rescord.MailTest` then
    holds it. With `dev_routes`, `/dev/mail` shows each one.
  - The build compiles the MJML, so a template uses a value as text or as
    the value of an HTML attribute, and no `if` or `for` around an MJML
    element. Each value is escaped. Write the text part by hand, with the
    same words.
  - The markup of an email has tables, inline styles and classes: the rule
    of classless markup is for the pages. A template still writes no
    colour but a value of `tokens.css`: the light value inline, and the
    dark value in the media query of the layout.
  - An email loads nothing: no image, no font and no stylesheet of any
    host. Do not name Ubuntu, Roboto, Lato, Open Sans or Droid Sans in a
    font stack: MJML then fetches the font from Google Fonts.
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
  - Each domain sets `check [aliases: true]` in its `boundary` block
    (ADR 0066), so a relationship and a signal listener are checked too. A
    relationship into another domain needs a `define` for that resource on
    its domain.
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
  - A signal (ADR 0067) is in `Rescord.<Domain>.Signals`, in the domain that
    emits it. That domain exports the module when another domain listens.
    - A listener action needs `authorize_if signal_in(Module, :signal)` in
      its policy, before `Rescord.Accounts.Checks.Granted`. Without it a
      listener that updates or destroys records changes nothing and returns
      no error. Test a listener as a person whose role has the grant of the
      emitter and no other, and look at the records afterwards
      (`Rescord.SignalsTest`).
    - A listener that must hold with the action that emits runs inline, the
      default. Work that reaches outside the database, such as an email,
      runs in a job: `delivery: {AshOban.Signals, queue: :default}`. Such a
      job has no actor.
    - When the action of a job writes its record in several steps, the
      nested writes pass `context: %{signal_path: input.context[:signal_path]}`,
      so their own `signal_in` policy holds, and each one filters on the
      state that the job expects, so a person who changed the record in
      the meantime wins (ADR 0100, `Rescord.Transfers.Actions.CopyFiles`).
      A count of the work is written at most once each 2 seconds, since
      each write makes the open pages read again (ADR 0096).
    - `emit ... where:` is evaluated before the hooks of the action, so it
      cannot see a value that a change sets. Emit with `dynamic?: true`
      and `Ash.Signals.emit/5` in an `after_action` then (ADR 0100).
    - A test that reads the email of an invitation calls
      `send_invitations/0` of `Rescord.AccountsFixtures` first. Oban runs
      no job by itself in a test.
    - Do not take `:ash_signals` out of the compilers in `mix.exs`, or the
      line `:temporal_safe_modules` out of `config/config.exs`.
  - **A page hears a change of another person** (ADR 0096). Each resource
    publishes by itself: `Rescord.Resource` gives it the notifier
    `Ash.Notifier.PubSub`, with `Rescord.Changes` as its module.
    - A page calls `LiveChanges.listen(socket, [Domain], &read_again/1)`
      in `mount/3`, before it reads. The function reads through the code
      interface, as the person of the page, and assigns. It does not
      assign a form again. For a `Cinder.collection` it calls
      `Cinder.refresh_table(socket, "<id>", silent: true)`. That is not
      enough for a collection of a temporal resource: its query holds
      the instant at which the page built it, so a refresh reads the
      past. Give such a query `as_of:` from an assign, and set the
      assign again in the function.
    - Never draw anything from a message. A `Rescord.Changes.Change` has
      no attribute of a record, and it must stay so: do not give a
      publication a `transform`, and do not broadcast a record on
      `Rescord.PubSub` by hand. A topic is not a policy.
    - A resource in the schema of an organisation needs no line. A
      shared resource (`shared?: true`) writes its publications, with
      the attribute that holds the id of the organisation
      (`Rescord.Transfers.Transfer`), or it goes on the list of the
      quiet resources in `Rescord.ChangesTest`, with the reason.
    - Several writes in one transaction use `Ash.transact/3`. A write
      inside `Rescord.Repo.transaction/1` loses its notification, and a
      test raises for it (`config :ash, :missed_notifications, :raise`).
    - In a test a page reads again at once: write, then render. A page
      does not hear the process that wrote, and the test process is not
      the page. For a page that has not read yet, open it inside
      `with_slow_changes/1` of `RescordWeb.ConnCase`. For a
      `Cinder.collection`, render with `render_changes/1` of the same
      module, which also waits for the read of the collection.
    - A `:for` over a list that reads again has a `:key`.
    - The chat of the assistant does not use this: it has its own topic
      (ADR 0069).
  - **No stream of LiveView, and no `assign_async`, without a reason**
    (ADR 0096). A list is an assign, or a `Cinder.collection`. A read
    that the page is for stays in `mount/3` until the metrics say that
    it is slow. An event that works outside the database while the page
    waits can use `start_async`.
  - Once there is authentication, every Ash call from a LiveView passes the
    actor explicitly. A refused read returns an empty result, not an error,
    so a test that reads asserts a non-empty result.
  - Each organisation has its own schema (ADR 0011). A resource that belongs
    to one organisation uses `multitenancy do strategy :context end`, and
    each call for it passes the tenant. Its migration goes in
    `priv/repo/tenant_migrations`.
  - Write `use Rescord.Resource, domain: ...`, never `use Ash.Resource`
    (ADR 0013). It makes the resource temporal, with a paper trail, a
    destroy that archives, and the schema of an organisation. State only the
    table, the attributes, the actions and the relationships. Change a
    default with `temporal?: false`, `paper_trail?: false`, `archive?: false`
    or `shared?: true`.
  - A resource with a workflow states `temporal?: false`, or it does not
    compile (ADR 0012).
  - A domain adds `AshPaperTrail.Domain` to its extensions, with
    `paper_trail do include_versions? true end`.
  - **One piece of work has one correlation id** (ADR 0101). Each
    version has `correlation_id`, `operation_id` and `causation_id`,
    which `Rescord.Resource` sets: write none of them by hand. A change
    that builds the options of a nested action gives it
    `context: Rescord.Correlation.context(changeset)`, beside
    `tenant: changeset.tenant`; `Rescord.CorrelationTest` fails for a
    file without it. A function of a domain that runs two actions or more
    starts with `opts = Rescord.Correlation.start(opts)` and gives those
    options to each action.
  - A change, validation or preparation for a temporal resource is a module
    that declares `temporal_safe?/1`. Pass `as_of:` as an action option, and
    use `now()` in an expression, never the wall clock.
  - A group of changes and validations that actions of one resource must
    keep the same goes in a pipeline (ADR 0086): `pipelines do pipeline
    :name do ... end end` before `actions`, and `pipe_through [:name]` in
    each action. Write one when the group has three lines or more, or when
    three actions or more take it; a smaller group stays in its actions.
    Inside a pipeline Ash runs each change before each validation, so a
    group with a validation before a change is not one pipeline. A pipeline
    holds no argument, no `accept` and no `emit`. `Rescord.Expenses.Expense`
    is the example.
  - A record that a person writes gets its author with
    `Rescord.Accounts.Changes.SetAuthor`, and a date of a thing that
    happened is checked with
    `{Rescord.Accounts.Validations.NotAfterToday, attribute: :the_date}`
    (ADR 0086). Do not write another one in a domain.
  - A request for a sign-in link answers at once (ADR 0019). It starts a
    supervised task and gives the same answer in each case: a known address,
    an address that Rescord does not know, and a fault. Do no work that
    depends on the address before the task starts. Never log a token or a
    link.
  - A file from another server is not trusted until it is checked: read it
    with `Rescord.Transfers.Archive.read/4`, which checks the signature of a
    recorded partner before it decrypts or decompresses, and show a copy
    only after `Rescord.Transfers.Snapshot.clean/1`. Never decode a file
    with `:erlang.binary_to_term/1`. The private keys stay encrypted under
    `RESCORD_KEY_SECRET`, and no page or log shows them (ADR 0043).
  - A new resource of a domain is in the export of the data, or
    `Rescord.Export.excluded/0` names it with the reason (ADR 0054).
    `Rescord.ExportTest` fails for a resource in neither.
  - A photo goes through `Rescord.Images.prepare/1` before it reaches the
    store (ADR 0055): it removes the metadata, the GPS position with the
    rest, and makes the thumbnail. Never store the bytes of a photo as a
    person sent them. A test makes a real image with
    `Rescord.StorageFixtures.photo/1`: libvips refuses a file that only
    starts like a JPEG. `prepare/1` runs the work of libvips through
    `Rescord.Images.Limit` (ADR 0056), which bounds the memory: call
    libvips for a file of a person through it, and nowhere else.
  - A file goes through `Rescord.Storage` (ADR 0041). Make each key with
    `Rescord.Storage.key/2`, and never from what a person sends. Read the
    type of a file from its first bytes, never from its name or from the
    browser. A page sends a file only through a controller that reads the
    record with the grants of the person.
  - A key gets its bytes one time: never put other bytes under a key that
    has a file. `bin/move-storage` copies the files of a server that
    works, and relies on it (ADR 0059). A new store implements each
    callback of `Rescord.Storage`, `list/0` and `files/0` too.
  - A resource that keeps a file holds the key in the attribute `key`,
    and the key of a thumbnail in `thumbnail_key`. Its domain has
    `file_keys/1` (`Rescord.Storage.Named.keys/3`) and is in
    `Rescord.Release.Files.domains/0`, or `bin/check-files` calls each of
    its files a leftover (ADR 0091). `Rescord.Release.FilesTest` names a
    resource that is left out. No code deletes a file of the store.
  - A test of the store of S3 with more than one request uses
    `Rescord.StorageFixtures.s3_store!/1`, which starts `Rescord.FakeS3`,
    a service in the memory of the test.
  - Limit how often an action runs with `extensions: [AshRateLimiter]` and a
    `rate_limit` section whose backend is `Rescord.RateLimit` (ADR 0020). Do
    not write a counter by hand. A test of a limit counts under a key of its
    own, so that tests share no count.
  - Policies and roles are our own system in the manner of `ash_grant`
    (ADR 0021). The policy of a resource of an organisation is a bypass for
    a root user and then the one check `Rescord.Accounts.Checks.Granted`.
    Give an action to a power with one line in the grants of its domain
    (ADR 0024 and ADR 0040). A role is a record with powers, so never write
    a role into a policy, and do not add `ash_grant` as a dependency. A new
    power takes a key in `Rescord.Accounts.Grants.power_keys/0`, words in
    `RescordWeb.RoleWords`, and a migration that gives it to the role with
    the key `:administrator`: a data migration, with its upgrade note
    (`docs/migrations.md`).
  - No action takes as input an attribute that decides who can do what:
    `root?` of a user, the role and the user of a member, and the powers
    that a person gives (`Rescord.Accounts.Validations.WithinPowers`). Mark such an
    attribute `writable? false`, and set it in a named action.
  - A page below `/o/:organisation` is in the live session `:organisation`,
    whose hook assigns `current_user`, `organisation`, `member` and
    `role`. Pass the user as the actor and the organisation as the tenant
    of each call. Show a form or a button only when
    `Rescord.Accounts.role_can?/3` says so.
- **Calendar feeds** (ADR 0074).
  - **The token of a feed is in one place: the address that the page
    shows one time.** Rescord stores its hash. Never put a token in a path,
    a line of the log, a version, a flash or a later render. The parameter
    is named `token`, which `:filter_parameters` leaves out of the log.
  - **A feed reads as its owner.** Each read for the content passes the
    user of the member as the actor and the organisation as the tenant.
    Only `Rescord.Calendars.fetch/3` reads with `authorize?: false`, to
    find the feed of a token, and it asks the policy of `subscribe` about
    the owner at each request.
  - **An event holds the least that is useful.** No name and no address
    of a member. The words that a person wrote are there only for a feed
    with `with_notes`. A new field of an event is a decision about what
    leaves Rescord.
  - **Each refusal of the address gets the same answer**, so a new reason
    to refuse returns `:error` from `fetch/3`.
  - A new dated thing is a clause of the function `calendar` of its
    domain, which reads as the actor of its options, and a clause of
    `RescordWeb.CalendarEvents`. The text of a calendar comes from
    `Rescord.Calendars.ICalendar` alone: never build a line by hand.
- **Settings** (ADR 0068). A new setting is in the environment only when
  Rescord needs it before the database, before the first sign-in, or when
  it describes the machine. Each other setting is an Ash resource with a
  page, and a new integration never gets a `RESCORD_*` variable or a line
  of `config :rescord`. A secret of a resource is an attribute under
  AshCloak in `Rescord.Vault`: the resource states `temporal?: false` and
  `ignore_attributes [:encrypted_<name>]` in its paper trail, the secret
  has an action of its own that refuses an empty value, and its name is in
  `:filter_parameters`. Do not add the package `cloak`.
- **The assistant, Ruby** (ADR 0069). It is built in phases, so a module
  that a rule names may not exist yet.
  - **Ruby acts as the member.** Each tool call passes the actor and the
    tenant of the conversation. Make the actor with
    `Rescord.Ruby.Actor.for/1` and nowhere else: it turns the root level
    off. No tool call passes `authorize?: false`.
  - **The loop cannot write.** `Rescord.Ruby.Gate` never answers `:ok` for
    a write tool. Only `Rescord.Ruby.confirm_proposal/2`, in the request of
    the member, runs an action that changes a record. Run it outside any
    other transaction.
  - **A tool is a line that a person wrote**, in `Rescord.Ruby.Catalogue`.
    Never pass `tools: true`. No destroy action is a tool. An action whose
    public inputs are wider than what Ruby may send gets a draft, or
    nothing. The actions of ADR 0069 that never have a tool stay without
    one, and the test of the catalogue fails for one. Only a domain that
    `Rescord.Ruby.CatalogueTest` names has the extension `AshAi`, and no
    resource declares a tool of its own. A read of a function of a domain
    is a digest in `Rescord.Ruby.Digests`: it calls that function as the
    member, says in `available?/2` who gets it, and refuses in `run/2` too.
  - **A tool result names each record** with a `ref`, a `label` and a line
    of `detail`, and puts the text of a person under a key that ends in
    `_text`. It holds no name and no email address of a member.
  - **The page draws what matters from data of the server**: a card, a
    link, a step. Never from the words of the model. `RubyMarkdown` drops
    each image and each link that is no record of this conversation.
  - **Never send the event `{:tool_result, ...}` of the loop to a page**:
    it holds raw records. Send the outline that code made.
  - **No setting of Ruby is a variable of the environment or a line of
    application config.** A provider is a row of `Rescord.Ruby.Provider`,
    and its key is under AshCloak in `Rescord.Vault`. Only
    `Rescord.Ruby.LLM.profile_of/1` decrypts a key. No page, no tool, no
    version row and no line of the log holds one.
  - **Ask `Rescord.Ruby.available?/2` whether a person can ask Ruby**, and
    `Rescord.Ruby.status/1` where Ruby stands for an organisation. Do not
    read `enabled` of the settings for that: Ruby is on only while the
    place of its provider is the one that a person of the organisation
    agreed to (`Rescord.Ruby.Changes.Agree`). A page of an organisation
    gets a provider only as `Rescord.Ruby.offers/1` gives it: its name
    and its place. The key of the place for an agreement comes from the
    providers that the page read, never from a field of the form.
  - **Each request goes through `Rescord.Ruby.LLM.Client`**, with the
    options of `Rescord.Ruby.LLM.Profile`. The system prompt is one
    constant text with no value in it. Inside a conversation the tools,
    the prompt and the stored turns never change: the messages only grow.
  - **A job writes each reply**, and `Rescord.Ruby.say/3` is the one way
    to start it: the trigger `respond` of `Rescord.Ruby.Message`, in the
    queue `ruby`. The job holds the id of the message, the organisation
    and the id of the member, and no word. It runs one time: do not raise
    `max_attempts`, the provider bills each try.
    `Rescord.Ruby.Changes.Respond` checks the member again
    (`available?/2`), and then `Rescord.Ruby.Replies` writes the rows with
    no policy. A reply always gets an end: a state, and a reason of
    `Rescord.Ruby.Reason` when it failed. The job raises only
    `Rescord.Ruby.Fault`, which has the shape of an error and none of its
    words, because Oban keeps the error of a job in its row. Keep
    `log_errors? false` on the trigger.
  - **The use of Ruby is counted in `Rescord.Ruby.Usage`**, one row for a
    member, a day of UTC and a model, with counts and no word. Never sum
    the replies for a cost: a conversation is deleted for real, and its
    use stays. `Rescord.Ruby.Allowance` sums a month against the
    allowance of the settings. `say` asks it, and `available?/2` does
    not: a member past the allowance still reads their conversations.
    The run after a member confirms a proposal is never refused for the
    allowance. A refusal of `say` for the allowance, for a full
    conversation or for the rate has a reason, which
    `Rescord.Ruby.refusal/1` gives. The event of telemetry of a reply has
    its state and its reason as tags, and no organisation, member or
    model.
  - **The header of a message is stored, and sent again as it was.**
    `Rescord.Ruby.Changes.Say` makes it with `Rescord.Ruby.Prompt`, from
    the rescue, the role, the day and the time zone. It is never an input,
    and holds no name, no address and no id of a person.
  - **No test calls a provider.** Use `Rescord.Ruby.ScriptedModel`, or
    `Rescord.FakeAnthropic` on `127.0.0.1`. The evaluation run is a Mix
    task, outside `mix test` and CI. `config/test.exs` names the scripted
    model under `:ruby_llm`. That line is a seam for the tests, and
    `Rescord.Ruby.LLM.Client` is its one reader: add no other.
  - **The evaluation set measures a real model**, and only a person
    starts it: `mix rescord.ruby.eval` asks a provider each question of
    `Rescord.Ruby.Eval.Cases` three times, against the made-up rescue of
    `Rescord.Ruby.Eval.Seed`, and `Rescord.Ruby.Eval.Score` checks each
    answer by code. It costs money, so never run it for a check of your
    own, and never add it to a workflow of a push. A change of the system
    prompt, of a tool, of the description of a tool, of the effort or of
    the default model goes with a run that a person makes. After a report
    of a wrong answer, the question becomes a case first. The key of a
    run is never a flag and never a variable of the environment: a row of
    a provider, or the standard input.
  - **Never log the text of a conversation**, a prompt, the arguments of a
    tool or its result. Log the ids, the names, the counts and the reason
    of a failure as an atom, never an error struct of ReqLLM: it holds the
    body of the request.
  - **The resources of a conversation have no bypass for a root user**, and
    are deleted for real: `temporal?: false`, `paper_trail?: false`,
    `archive?: false`.
  - **A new tool** takes a line in the catalogue, words in
    `RescordWeb.RubyWords`, and a question in the evaluation set.
- **The log** (ADR 0077).
  - A line holds no name and no address of a person, no text that a person
    typed, no token, no link, no key, no file, and no argument of a job.
    It holds ids, counts, and the names of modules.
  - Never write the message of an error or an inspected value: the
    arguments of a call of `Logger` use no `inspect` and no function of
    `Exception`. Write `Rescord.Log.reason(error)` for a failure, and
    `Rescord.Log.shape(value)` for any other value.
    `Rescord.LogRulesTest` fails for the opposite.
  - `error` is for work that Rescord lost, or a thing that needs the
    operator. `warning` is for a thing that failed while Rescord goes on
    or tries again. `info` is for what an operator wants on a normal day.
  - Code that starts work for a person or an organisation outside a
    request, a page or a job calls `Rescord.Log.context/1` with their
    ids. A request, a page and a job have their fields already.
  - Do not attach `Oban.Telemetry.attach_default_logger/1`, which writes
    the arguments of each job. `Rescord.Log.Jobs` writes the lines of the
    jobs.
  - Do not take `Rescord.Log.attach/0` out of the start of the
    application: without it, a page that stops with a fault writes the
    form of the person.
- **Metrics** (ADR 0077). A new metric is a line of `Rescord.Metrics`, or
  of `RescordWeb.Telemetry` for a request or a page. Its name starts with
  `rescord.`, and a time is a `duration/2` in milliseconds. A tag is a
  module, an atom or a number that the server sets: never an id, a name,
  the path of a request or the name of an event of a page, which a client
  sends. A number about the work of a rescue is a row of a page, not a
  metric. Do not add AshMetrics, PromEx or OpenTelemetry without the
  maintainer.
- **Errors** (ADR 0077). A new failure of our own that can reach a person
  is a module with `use Splode.Error, fields: [...], class: :invalid` (or
  `:forbidden`), in the domain that returns it. Do not return a sentence
  from a change or an action: Ash makes it `Ash.Error.Unknown`. Do not
  make a Splode root of our own. An atom, such as `{:error, :busy}`, is
  for a result that the caller matches and that no person sees. Put the
  module in `Errors` of its domain, give it a reason that is an atom and
  never a value that a person typed, and let a page say it with
  `Rescord.Accounts.error_messages/1`, which takes one such error too.
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
  Read what `mix deps.get` prints, each time: it names a package with a
  security advisory (`VULNERABLE!`) or a retired one (`RETIRED!`). Update
  such a package, or say why it stays.
  CI runs `mix hex.audit`, which fails on either (ADR 0048). An advisory that
  cannot reach Rescord goes in `hex: [ignore_advisories: ...]` in `mix.exs`,
  with the reason and when to take it out. A change to `mix.lock` also
  changes the hash of `fetchMixDeps` in `nix/package.nix`.
- **Tests.** A test that needs Postgres uses `Rescord.DataCase` or
  `RescordWeb.ConnCase`, which carry the `:postgres` tag. Any other test uses
  `ExUnit.Case` (ADR 0006).
  - **A page test finds what a person finds** (ADR 0107). It uses
    PhoenixTest with `use RescordWeb.Roles` (`browser: true` in a browser
    test), and finds by landmark, role and name:
    `click(region("Lots") |> button("Take off B-1"))`,
    `fill_in("Quantity", ...)`, `assert_has(main() |> heading(level: 1),
    text: "Meadow hay")`. It does not send the event of a button that it
    could press, match `=~` on the whole page for words that are in a
    region, find a thing that has a name with `:first-child`,
    `:nth-child` or `>`, or read words with a script in `evaluate`.
  - An id, a `data-` attribute or a raw event stays only where it is what
    the test holds: an id of an address or of `focus.ts`, records that only
    an id tells apart, the controls that Cinder writes, `data-state` and
    `data-label`, the state of the connection, and an event that the page
    does not offer (sent with `unwrap/2`, to test a refusal).
  - A component test reads its HTML with the queries of
    `RescordWeb.Roles` (`has?/2`, `text/2`, `names/2`). A response that is
    no page (ICS, CSV, PDF, JSON) stays on `Phoenix.ConnTest`.
  - The tests of an area move to this one area at a time (issue 33). A
    test that you change moves with it.
  - A test that keeps a file tags itself `:tmp_dir` and calls
    `Rescord.StorageFixtures.disk_store!/1`, so each test has a directory of
    its own. No test reaches a real store.
  - A test that creates an organisation is `async: false`: a new schema
    takes a lock on the users, and two at one time stop each other
    (ADR 0022).
  - `Rescord.AccountsFixtures` makes a user, a root user, an organisation
    and a member, and signs a connection in.
  - For a rule about who can do what, change the rule and see a test fail.
  - `Rescord.PolicySweepTest` asks the policies about each action of each
    resource as the actors who must be refused (ADR 0063). It fails for a
    new action that an actor can run with no grant. Then give the resource
    its policy, or add the grant to the grants of the domain. Add the
    action to `open_on_purpose/0` of the test only when it is open on
    purpose, with the reason and the test that holds what it still keeps
    from the actor.
  - **A browser test** uses `RescordWeb.FeatureCase` and is in
    `platform/test/rescord_web/features/` (ADR 0023). It drives a real
    Chromium with `PhoenixTest.Playwright`. Write one for what only a
    browser shows: a control that a person finds by its words, the script of
    a page, a session that reaches a LiveView. Hold each rule with a request
    test too, which is faster.
    - The devenv shell has the driver and the browser. Outside it, `mix test`
      leaves the browser tests out and says so in its first lines. Do not
      report a run as complete when it says that.
    - A browser test that reads an email, or that creates an organisation,
      is `async: false`.
    - After a click that opens a LiveView, call `assert_connected/1` before
      the test presses a control of that page.
    - Never add an npm package for the browser tests: the driver is the one
      of nixpkgs.
- **A resource of an organisation** (ADR 0025).
  - It is temporal by default. Each change, validation and preparation that
    you write for it declares `temporal_safe?/1`, and reads the instant of
    the action and not the clock.
  - An attribute has the name of its column: no `source`, and so no `?` in
    the name of a boolean (ADR 0027). The compiler refuses the opposite.
  - When you give an attribute a new name, read the migration. The generator
    writes a new column and the removal of the old one, which loses each
    value. Change that to `rename`.
  - A relationship between two temporal resources names its period keys:
    `temporal_keys {:valid_at, :valid_at}`.
  - After `mix ash.codegen` makes a tenant migration, run
    `mix run --no-start -e "Rescord.TenantMigrations.repair!()"`, and copy
    nothing by hand. `mix test` fails while a tenant migration has a fault.
  - A fact that can come again for the same record, such as a tie, uses
    `archive?: false`: its removal ends its period. An archived row with an
    open period would refuse the same fact later.
  - The domain holds its grants in a module of its own, and
    `config :rescord, :grant_sources` names it (ADR 0024). Without that,
    each member is refused.
  - A test reads as of a past instant where the history matters.
- **A page with a form.** A page that stays open after a write keeps what
  the person typed, so open the page again after a write
  (`push_navigate` to its own path). Read each field of the form with
  `non_blank/1` of `Shoddy.Strings`, which each LiveView imports: it
  returns `nil` for a blank field and for a value that is not text.
  A line of help for one field is the `hint` of `<.input>`, which ties
  the line to the field with `aria-describedby`.
  `<.problems list={@problems} />` says
  what an action refused. Draw it in the form that the person sent when
  that form is far down the page, and below the header in each other case.
  In a page test, look for the alert of
  the page with `assert_has(session, main() |> alert())` of
  `RescordWeb.Roles`: the layout always holds a hidden element with
  `role="alert"`, so a search of the text for that role finds one on each
  page.
- **Quantities and units** (ADR 0071). A number with a unit is a
  `Rescord.Units.Quantity`, and `Rescord.Units` converts and calculates:
  `convert/3`, `multiply/2`, `divide/2`. Never write a factor such as
  `1000` in other code, never use a float for a quantity, and never round
  inside a calculation: round for the page, with `Quantity.round/2`.
  - A new attribute or argument that holds a quantity uses
    `Rescord.Units.Types.Quantity` with the constraint `dimension`, and not
    a decimal beside a text. A unit alone uses `Rescord.Units.Types.Unit`.
  - A value of the list of units of an organisation is a name.
    `Rescord.Lists.known_unit/1` says what it means, and gives `:error` for
    a name that the catalogue does not know. Then ask the person, and do
    not guess.
  - A page writes a quantity with `RescordWeb.UnitWords.quantity/1`, which
    keeps each digit.
  - A new unit takes a line in the catalogue of `Rescord.Units`, words for
    a new dimension in `RescordWeb.UnitWords`, and a line with its factor
    in `Rescord.UnitsTest`.
- **Measurements and their standard unit** (ADR 0094). A measure kind can
  name its standard unit. A measurement keeps the number and the unit that
  the person recorded: never store a converted value, and never change
  what was recorded to fit the standard unit.
  - Code that shows a measurement uses `Rescord.Journal.standard/1`, and a
    page writes it with `RescordWeb.MeasurementWords.measurement/1`. Do
    not write `value` beside the label of `unit` by hand.
  - The units that a form offers come from `RescordWeb.MeasurementUnits`,
    and the rule of the journal from `Rescord.Lists.units_for/2`. Both
    read `Rescord.Lists.accepted_units/2`: change the rule there.
  - A read that shows a measurement loads
    `measure_kind: [standard_unit: [:label]]` and `unit: [:label]`, as
    `Rescord.Journal.entries/2` does. Without the standard unit loaded,
    the measurement is shown as it was recorded.
- **Charts** (ADR 0080). A chart is SVG that the server writes, with
  `line_chart/1` or `sparkline/1` of `RescordWeb.ChartComponents`, and
  the geometry of `RescordWeb.Chart`. Do not add a chart library, and do
  not write a script for a chart.
  - A place in a chart is a percentage, and the `<svg>` has no `viewBox`.
    Only a line is in a nested `<svg>` that stretches. A label is HTML
    beside the `<svg>`, or SVG text at a percentage.
  - A number of a chart is a `Decimal`, and the label of a tick comes from
    `Chart.ticks/3`. Never use a float for a value.
  - A `line_chart` gets a `title`, which is the name of the image, and a
    `summary`, which is its description and the caption that each reader
    sees. Give each chart its values as a table on the same page: a chart
    never holds a value that the page says nowhere else. No part of a
    chart takes the keyboard focus.
  - A chart has one series in `--accent`, and lines for a context in
    `--field`. It never uses the colour of a state, and a change has no
    colour of good or bad. A chart with a colour for each series needs new
    tokens and a decision of the maintainer.
  - The measurements of a resident are series:
    `Rescord.Journal.series/2`, which chooses the unit and converts. A
    page writes a value and a change with `RescordWeb.MeasurementWords`.
- **Tools** (ADR 0072). A tool is a page below `/o/:organisation/tools`
  that helps with a piece of work and stores nothing: a card in
  `RescordWeb.ToolComponents.tools/1`, a route, and a LiveView with
  `section={:tools}`. Each member can open it, and what it reads from the
  records it reads as the member.
  - The dose calculator is `Rescord.Dosage` and `RescordWeb.DoseLive`. It
    is an aid to arithmetic and **knows no medication**: never give it a
    dose rate, a list of medications, or a warning that a dose is too
    much or is safe. That would be a formulary, and a new decision of the
    maintainer.
  - Its guards are in ADR 0072, and `Rescord.DosageTest` holds each one.
    A number comes through `Rescord.Dosage.parse_number/1`, a unit is one
    of the lists of `Rescord.Dosage`, the result goes when a field
    changes, and the note to check with a vet is on the page at all
    times.
  - A new problem or note of `Rescord.Dosage` takes words in
    `RescordWeb.ToolWords`.
  - What the calculator takes from a record, the weight of a resident or
    the strength of an item, it names with its source, and drops when the
    person changes the field or chooses another record. A form that
    writes a strength uses `RescordWeb.ToolComponents.strength_controls/1`
    and `Rescord.Dosage.strength/3`.
- **Reports** (ADR 0076). A report is a PDF that a generic action of
  `Rescord.Reports.Report` returns, through `Rescord.Reports.Render`.
  - A new report takes: a module of facts below `Rescord.Reports.Facts`
    (and its entry in `Rescord.Reports.Facts`), a module of words below
    `RescordWeb.ReportWords` (and its entry there), a template
    `priv/typst/<name>.typ` with its `template` in the resource, the
    action with its rate limit, the function of the domain and its name in
    `Rescord.Reports.reports/0`, the grant in `Rescord.Reports.Grants`,
    and a route of `RescordWeb.ReportController`.
  - The facts read through the functions of the other domains, with the
    options of the request as they are. **Never pass `authorize?: false`
    in a report.**
  - The words give text that is ready to show: a template formats nothing
    and decides nothing about a record. A template starts with
    `#import "look.typ": *` and `#import "data.typ": d`, and uses the parts
    of `look.typ`.
  - **Never put a value of a record into the source of a template**, and
    never call `eval` in a template: the data is the value `d` alone.
  - The fonts of a report are the files of `priv/typst/fonts`. A report
    is not PDF/A.
  - **A report is on A4 or on US Letter** (ADR 0093): the argument `paper`
    of its action, or the paper of the organisation, which
    `Rescord.Reports.Render` puts into `d.frame.paper`. A template never
    names a paper. It has one layout for both: give a width as a fraction
    of the page, or as a size that fits the smaller side of each paper,
    and look at a new template on both. A new action takes the argument
    `paper` as the others do, and its path passes `paper(params)`. A link
    to a report with no `paper` gets the paper of the organisation.
  - To look at a report, render it in a scratch test with
    `Rescord.ReportsFixtures.refuge!/1`, write the bytes to a file, and
    read the pages as pictures (`pdftoppm -png`). Do not commit the
    scratch test.
  - A new version of `ash_typst` takes the new version and the new hashes
    in `nix/package.nix`, from the checksum file of the package.
- **Expenses and money** (ADR 0082). Rescord is not an accounting system:
  no ledger, no payment, no conversion.
  - **An amount is an `AshMoney.Types.Money`**, never a float and never a
    decimal beside a text. No action takes a currency: the argument
    `amount` is a decimal, and `Rescord.Expenses.Changes.SetAmount` makes
    the money in the currency of the organisation.
  - **Never add two currencies.** A sum is `Rescord.Expenses.sum/1`, with
    one amount for each currency, and a page writes each one.
  - A page writes an amount with `RescordWeb.ExpenseWords.money/1`, which
    is `RescordWeb.Locale.money/1`. A form and a CSV file hold a plain
    number, and the code of the currency apart.
  - **No action of an expense takes the state, the author, or the person
    who decided or paid back.** An action that changes the state has the
    filter on the state.
  - **A validation that reads as the actor is `before_action?: true`**,
    so the policy answers first: the category, the resident, the payer,
    the expense of a receipt.
  - A page asks `Rescord.Expenses.can?/4` about a button, and
    `Rescord.Expenses.list_query/2` gives the query of the list. A member
    reads only their own expenses, so a page, a file and a report read
    with the options of the person, and never with `authorize?: false`.
  - A new power goes at the end of `@power_keys` of
    `Rescord.Accounts.Grants`, with a migration of the organisations whose
    time is after each other one: the order of the keys is the order in
    which the migrations add the powers.
  - The list of the currencies is `Rescord.Accounts.currencies/0`. The
    data of Localize marks each code as tender, so that function names
    the codes that are no money.
  - **The tax of an expense is a number from the receipt** (ADR 0089).
    Add no rate, no tax code and no code that works a tax out from an
    amount, or an amount from a tax. The argument `tax` is a decimal, and
    `Rescord.Expenses.Changes.SetTax` makes the money in the currency of
    the amount. No tax (`nil`) is not a tax of zero. A page has the field
    and the form of the correction only while the organisation names a
    tax (`tax_name`), and writes that name with
    `RescordWeb.ExpenseWords.tax_name/1`. A sum of the tax is
    `Rescord.Expenses.tax_sum/1`.
- **The journal page** (ADR 0092). The entries are a collection of
  Cinder, so the page does not hold them.
  - An event that names an entry or a file by its id reads it with
    `Rescord.Journal.entry_of/3` or `attachment_of/3`: as the person,
    and only from the journal of this resident. Never read it by the id
    alone.
  - A link from another page to one entry is `journal?entry=<id>`, never
    `journal#entry-<id>`: the entry can be on a later page.
  - The parameters `episode`, `entry` and `new` are of the page. Each
    other parameter is of Cinder: the page gives it back in a link, and
    does not read it. A new parameter of the page must not have the name
    of a field of a filter.
- **The tasks page** (ADR 0097). The tasks of a day are a collection of
  Cinder, so the page does not hold them.
  - An event that names a task by its id reads it with
    `Rescord.Tasks.task_of_day/3`: as the person, and only from the tasks
    that the day of the page shows. Never act on a task by the id alone.
  - The parameter `day` is of the page. Each other parameter is of Cinder:
    the links to another day give them back, without `page`.
  - A link from another page to one task in its day is
    `tasks?day=<date>#task-<id>`. The id is on the title of the task,
    because Cinder writes the row. The title links to the page of the task,
    `tasks/<id>` (ADR 0106), which has its comments.
- **Comments and notifications** (ADR 0106).
  - A page shows the comments of its record with the live widget
    `RescordWeb.Widgets.Comments` (`assign_widget/3` in `mount/3`, the
    component in the render). It takes the subject `{kind, id}` of a record
    that the page read as the person. A new kind of record is a column of
    `Rescord.Comments.Subject`, a migration with the check of one column,
    and a read in `readable?/2`.
  - The words of a comment go to the page only through
    `RescordWeb.Markdown.markdown/1`. Never `raw/1` them, and never give
    the Markdown a node that it does not render itself.
  - What leaves the server is `Rescord.Notifications.Message`: the
    organisation, the sentence of the kind, the address of the page of
    notifications. Never put a record, a person or a word of a comment in
    a push or a topic of ntfy, and never log a subscription or a topic.
  - A new channel is a module of `Rescord.Notifications.Channel`, with its
    settings in `Rescord.Notifications.Settings` (AshCloak for a secret,
    the page `/root/push`), never in the environment.
  - A new kind of notification is an atom of `Notification.kind`, its
    sentence in `Message.sentence/1` and `RescordWeb.CommentWords`, and a
    row of the preferences.
  - The service worker is `assets/js/sw.ts`, built to `priv/static/sw.js`
    (not in git). It has no handler of `fetch`; add one only with an ADR.
- **The conditions of a resident** (ADR 0083). A condition of a resident
  is an episode, `Rescord.Journal.Episode`.
  - Only a diagnosis starts an episode, through
    `Rescord.Journal.Changes.LinkEpisode`. Add no form and no action that
    starts one for a person, and no migration that makes one from old
    entries.
  - An entry names an episode of its own resident alone. A page reads the
    id of an episode from the episodes that it has in hand, never from
    what the browser sends.
  - A new count is a function of `Rescord.Journal` that reads as the
    actor, and a list of `RescordWeb.ConditionComponents.counts/1`.
- **Dates.** Today for an organisation is `Rescord.Accounts.today/1`, in its
  time zone (ADR 0026). Never use `Date.utc_today/0` or `DateTime.to_date/1`
  for a rule or a page of an organisation; `Rescord.Accounts.local_date/2`
  turns an instant into its date there. A test that needs two different
  dates at one instant uses two zones that are far apart, and no clock of
  its own.
- **A domain reads the versions of its own resources**, and no other domain
  does (ADR 0035). The policy of a version resource refuses each actor
  (ADR 0063): the function reads the record that decides first, with the
  options of the caller, then the versions with `authorize?: false`, and
  returns nothing when the caller cannot read the record.
  `Rescord.History.changes/1` says what the versions mean.
- **What needs somebody is a row of its domain** (ADR 0065). The first
  page of an organisation shows what `Rescord.Attention.parts/2` gathers
  from the function `attention` of each domain. For a new thing that a
  member must act on, add a row there: read it as the actor, give it only
  to a role with the grant that puts it right, keep the limit and the
  total, and add its clause to `row/1` of `RescordWeb.AttentionComponents`
  with a link to the page where the person acts. A row has no button.
- **An action that changes a state has a filter on that state**
  (`change filter(expr(state == :due))`, ADR 0032). The state machine reads
  the record that the caller has in hand, which can be old. The filter
  refuses the second of two members with `Ash.Error.Changes.StaleRecord`.
- **A change to what a user is reaches each open page** (ADR 0036). After a
  page changes the root grant or the role of a person, or takes a member
  out, it calls `RescordWeb.UserAuth.disconnect/1` for that user. A
  LiveView keeps the user that it read when it connected, and the root
  bypass reads `root?` from that user.
- **A removal reaches what names the record** (ADR 0036). An action that
  removes a record ends the ties of that record in the same transaction, or
  refuses while something still names it. A reader leaves out a record that
  names one that it cannot read.
- **Code that runs with no person**, such as a job, calls a function of the
  domain that passes `authorize?: false`. An action that only Rescord runs
  is in no list of grants, so the policy refuses each role (ADR 0033). A
  function that depends on the time takes `now` as an argument, so that a
  test gives it.
- **A resource with a state machine** is not temporal (`temporal?: false`).
  It names a record of a temporal resource by a plain id, with
  `define_attribute? false` and `temporal_keys {nil, :valid_at}` on the
  relationship: the database can hold no key between the two (ADR 0032).
- **A `<details>` has an id** (ADR 0031). A form that a person does not
  always need is in a `<details>` that is closed at first. Without an id it
  closes when the page says what is wrong, with what the person typed.
- **A refusal has one shape.** A change or a validation that adds an error
  for a person with no sign-in gives that person `invalid` where the policy
  gives `forbidden`. Let the policy refuse: do nothing in the change when
  there is no actor.
- **Words for a value.** A page never shows an atom. A fixed list has a word
  for each value in a module such as `RescordWeb.ResidentWords`, and a test
  holds the words to the type.
- **Dates and numbers that a person reads** (ADR 0075). A page writes a
  date, a time of day and a number through the words modules
  (`ResidentWords.date/1`, `TaskWords.day/1` and `time/1`,
  `JournalWords.time/1` and `number/1`), which call `RescordWeb.Locale`,
  the one module that calls `Localize`. They have the forms of the locale
  of the organisation, which the hook `:require_organisation` sets for
  the process. A task that a page starts gets the tag of
  `RescordWeb.Locale.current/0` and calls `put/1`. A number never rounds.
  A test that holds a time of day holds the form of the default locale,
  `8:30 am`. After an update of `localize`, run
  `mix localize.download_locales` and commit the files of
  `priv/localize/locales`: `Rescord.LocaleFilesTest` fails until then.
- **Atoms.** Never create atoms from text that a client sends.
- **Branches.** Work is on `main` for now (the maintainer, 15 November 2026).
  Commit there and push `main`, with no pull request. A session whose own
  instructions name another branch still pushes `main`.

## Where things live

| Path | Contents |
| --- | --- |
| `platform/lib/rescord/` | domains and resources (Ash) |
| `platform/lib/rescord/accounts/` | users, the sign-in, organisations, members, grants |
| `platform/lib/rescord/lists/` | the lists of values: a base list and a list of the organisation for each dimension |
| `platform/lib/rescord/residents/` | the residents and the facts about them, their families and groups |
| `platform/lib/rescord/locations/` | the locations, the tie that puts one inside another, and the placements |
| `platform/lib/rescord/journal/` | the journal entries and the facts of each medical kind; the conditions of a resident (ADR 0083) |
| `platform/lib/rescord/journal/series.ex` | the measurements of one kind over time, in one unit, for a chart (ADR 0080) |
| `platform/lib/rescord/journal/standard.ex` | a measurement in the standard unit of its kind, beside what was recorded (ADR 0094) |
| `platform/lib/rescord/photos/` | the photos of the residents, their albums and the profile pictures (ADR 0055) |
| `platform/lib/rescord/images.ex` | a photo made safe to keep, and its thumbnail, with libvips (ADR 0055) |
| `platform/lib/rescord/history.ex` | reads the versions of a temporal resource as changes, for the timeline |
| `platform/lib/rescord/inventory/` | the items, the lots, the suppliers, the stock movements and the reorder levels |
| `platform/lib/rescord/tasks/` | the tasks, their states and their subjects; the routines, their patterns and the job that makes their tasks |
| `platform/lib/rescord/units.ex`, `units/` | the units of measure, the quantities and their arithmetic, and the two Ash types (ADR 0071) |
| `platform/lib/rescord/tenant_migrations.ex` | the repair of a tenant migration (ADR 0025) |
| `platform/lib/rescord/resource.ex` | the base of each resource, and its checks |
| `platform/lib/rescord/changes.ex` | what a page hears when a record changes: the topics, the message with no record, and the module that the notifier of each resource calls (ADR 0096) |
| `platform/lib/rescord/rate_limit.ex` | the counts of the rate limits (Hammer, in ETS) |
| `platform/lib/rescord/dosage.ex` | the arithmetic of a dose, for the dose calculator of the tools (ADR 0072) |
| `platform/lib/rescord/reports.ex`, `reports/` | the reports as PDF: the actions, the facts of each report, and the render (ADR 0076) |
| `platform/lib/rescord_web/report_words.ex`, `report_words/` | the words of each report |
| `platform/priv/typst/` | the Typst templates of the reports, their shared look, and the fonts with their licence |
| `platform/lib/rescord/log.ex`, `log/` | what the log holds and keeps out: the fields of a line, the safe text of a failure, the crash reports, the lines of the jobs (ADR 0077) |
| `platform/lib/rescord/metrics.ex`, `platform/lib/rescord_web/telemetry.ex` | the metrics, and the endpoint that a collector reads (ADR 0077) |
| `platform/lib/rescord/expenses.ex`, `expenses/` | the expenses, their receipts, their states and their grants (ADR 0082) |
| `platform/lib/rescord/storage/compare.ex`, `storage/named.ex`, `release/files.ex` | the comparison of the store with the records, for `bin/check-files`: the groups and the report, the keys that a resource names, and the read of both (ADR 0091) |
| `platform/lib/rescord/storage/upload.ex` | the check of a file that a person sends: its type from its bytes, its size, and a photo made safe (ADR 0041, ADR 0082) |
| `platform/lib/rescord_web/expense_words.ex` | the words of the expenses: the states, the amounts, the rows of the CSV file |
| `platform/lib/rescord/attention.ex` | what needs somebody now in an organisation, which each domain gives (ADR 0065) |
| `platform/lib/rescord/export.ex`, `export/` | the export of the data of an organisation as CSV in a ZIP (ADR 0054) |
| `platform/lib/rescord/vault.ex` | the vault of the settings: what encrypts a secret attribute, and the change of its secret (ADR 0068) |
| `platform/lib/rescord/ruby.ex`, `ruby/` | the assistant, Ruby: the providers and their keys, the one module that sends a request, the settings of an organisation, the conversations, the tools, the prompt, the job that writes a reply, and the evaluation set under `ruby/eval/` (ADR 0069) |
| `platform/lib/mix/tasks/rescord.ruby.eval.ex` | the task that runs the evaluation set of Ruby against a real model. Only a person starts it |
| `platform/lib/rescord_web/ruby_words.ex` | the words of the assistant: the services, the reasons of a failure, the amounts of money, and where Ruby stands for an organisation |
| `platform/lib/rescord/comments.ex`, `comments/` | the comments of a record, the follows, the two powers, and the signal of a new comment (ADR 0106) |
| `platform/lib/rescord/notifications.ex`, `notifications/` | the notifications, the preferences, the channels (Web Push with its encryption, and ntfy), the subscriptions, the topics and the settings of the server (ADR 0106) |
| `platform/lib/rescord_web/markdown.ex` | the Markdown subset of a comment, rendered to safe HTML (ADR 0106) |
| `platform/assets/js/sw.ts`, `platform/assets/js/push.ts`, `platform/priv/static/manifest.webmanifest` | the service worker, the hook that turns notifications on for a device, and the manifest of the installable app (ADR 0106) |
| `platform/lib/rescord_web/live/` | page LiveViews |
| `platform/lib/rescord_web/widgets/` | live widgets: state, hooks, render |
| `platform/lib/rescord_web/widget.ex` | bookkeeping shared by widgets |
| `platform/lib/rescord_web/live_changes.ex` | a page listens for the changes of its domains, waits a moment, and reads once (ADR 0096) |
| `platform/lib/rescord_web/components/` | function components and layouts; the parts of the pages of each area (ADR 0037) |
| `platform/lib/rescord_web/chart.ex`, `components/chart_components.ex` | the geometry of a chart, and the line chart and the sparkline as SVG (ADR 0080) |
| `platform/lib/rescord_web/controllers/catalogue_html.ex`, `catalogue_html/examples/` | the catalogue of the components at `/dev/components`, and a template for each example (ADR 0095) |
| `platform/assets/js/` | `app.js` of the generator, and our TypeScript modules |
| `platform/test/rescord_web/features/` | the browser tests (ADR 0023) |
| `platform/assets/css/app.css` | the order of the CSS layers, and their imports |
| `platform/assets/css/layers/` | the classless stylesheet, one file per layer |
| `platform/assets/css/layers/tokens.css` | the colours, the typeface and the sizes of Scrubs (ADR 0015) |
| `platform/assets/css/layers/vendor.css` | the look of the markup that Cinder renders |
| `platform/lib/rescord_web/cinder_theme.ex` | the theme of each collection: almost no class |
| `platform/priv/static/fonts/` | the font files that the application serves, with their licence |
| `platform/AGENTS.md` | the usage rules of the dependencies, written by `mix usage_rules.sync` |
| `devenv.nix`, `devenv.yaml`, `devenv.lock` | the toolchain (ADR 0001) |
| `platform/lib/rescord/release.ex`, `platform/rel/` | the tasks of a release, with the rehearsal of an upgrade in `release/rehearsal.ex` (ADR 0081), and its scripts in `bin`: `server`, `migrate`, `bootstrap-root`, `check`, `backup`, `restore`, `move-storage`, `rotate-vault` and `check-files` (ADR 0044, ADR 0049, ADR 0050, ADR 0059, ADR 0068, ADR 0091) |
| `platform/lib/rescord/storage.ex`, `storage/` | the stores of the files, a directory and a bucket of S3, and the move from one into the other (ADR 0038, ADR 0059) |
| `platform/Dockerfile`, `deploy/` | the image, the Compose file, and the systemd unit |
| `flake.nix`, `nix/` | the Nix package, the NixOS module and its test |
| `scripts/release-tarball.sh` | the tarballs of the release |
| `docs/self-hosting.md` | the guide for an operator |
| `docs/migrations.md`, `scripts/check-upgrade-notes.sh` | the rules of a migration and of its upgrade note, and the check that each migration has one (ADR 0073) |
| `.github/workflows/`, `scripts/ci-catch-up.sh` | CI, the flake check, the release (ADR 0047), the jobs side by side (ADR 0103), and the run of CI that `main` gets when pushes cancel each other (ADR 0078) |
| `.github/workflows/mutation.yml`, `.github/scripts/muex_summary.exs` | mutation testing with muex, and the summary of its report (ADR 0104) |
| `.gitleaks.toml`, `scripts/check-secrets.sh` | the scan for secrets and for what belongs to one deployment (ADR 0064) |
| `CHANGELOG.md` | the changes of each release, which become its notes |
| `docs/architecture.md`, `docs/adr/` | the design and its decisions |
