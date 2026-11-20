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
mix test                          # sets up the test database, builds the assets, runs a server on port 4002
iex -S mix phx.server             # http://localhost:4000
mix precommit                     # compile --warnings-as-errors, unlock unused deps, format, test
mix usage_rules.sync              # write platform/AGENTS.md again, after a change to the deps
```

The packages of a release (ADR 0044), from the root of the repository:

```sh
docker build -t rescord:local platform     # the image
nix build .#rescord                        # the Nix package
nix flake check                            # the package and a NixOS test of the module
scripts/release-tarball.sh amd64 arm64     # the tarballs in dist/, with Docker buildx
```

After a change to `platform/mix.lock`, set the hash of `fetchMixDeps` in
`nix/package.nix` again: `nix build` prints the new one.

CI runs the checks of each push in the devenv shell (`.github/workflows/ci.yml`,
ADR 0047). To release a version: change `version` in `platform/mix.exs`, add
its section at the top of `CHANGELOG.md`, and commit both on `main`. Then run
the workflow Release on `main` from the Actions page, which makes the tag
such as `v0.2.0`, or push that tag. `release.yml` checks the flake, and
publishes the image, the tarballs and the GitHub release.

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
  - Icons are our own inline SVGs in `CoreComponents.icon/1`, always
    `aria-hidden`. There is no icon library.
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
  - A change, validation or preparation for a temporal resource is a module
    that declares `temporal_safe?/1`. Pass `as_of:` as an action option, and
    use `now()` in an expression, never the wall clock.
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
  - A file goes through `Rescord.Storage` (ADR 0041). Make each key with
    `Rescord.Storage.key/2`, and never from what a person sends. Read the
    type of a file from its first bytes, never from its name or from the
    browser. A page sends a file only through a controller that reads the
    record with the grants of the person.
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
    the key `:administrator`.
  - No action takes as input an attribute that decides who can do what:
    `root?` of a user, the role and the user of a member, and the powers
    that a person gives (`Rescord.Accounts.Validations.WithinPowers`). Mark such an
    attribute `writable? false`, and set it in a named action.
  - A page below `/o/:organisation` is in the live session `:organisation`,
    whose hook assigns `current_user`, `organisation`, `member` and
    `role`. Pass the user as the actor and the organisation as the tenant
    of each call. Show a form or a button only when
    `Rescord.Accounts.role_can?/3` says so.
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
- **Tests.** A test that needs Postgres uses `Rescord.DataCase` or
  `RescordWeb.ConnCase`, which carry the `:postgres` tag. Any other test uses
  `ExUnit.Case` (ADR 0006).
  - A test that keeps a file tags itself `:tmp_dir` and calls
    `Rescord.StorageFixtures.disk_store!/1`, so each test has a directory of
    its own. No test reaches a real store.
  - A test that creates an organisation is `async: false`: a new schema
    takes a lock on the users, and two at one time stop each other
    (ADR 0022).
  - `Rescord.AccountsFixtures` makes a user, a root user, an organisation
    and a member, and signs a connection in.
  - For a rule about who can do what, change the rule and see a test fail.
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
  `<.problems list={@problems} />` says
  what an action refused. Draw it in the form that the person sent when
  that form is far down the page, and below the header in each other case.
  In a page test, look for the alert of
  the page with `has_element?(view, "main p[role=alert]")`: the layout
  always holds a hidden element with `role="alert"`, so a search of the
  text for that role finds one on each page.
- **Dates.** Today for an organisation is `Rescord.Accounts.today/1`, in its
  time zone (ADR 0026). Never use `Date.utc_today/0` or `DateTime.to_date/1`
  for a rule or a page of an organisation; `Rescord.Accounts.local_date/2`
  turns an instant into its date there. A test that needs two different
  dates at one instant uses two zones that are far apart, and no clock of
  its own.
- **A domain reads the versions of its own resources**, and no other domain
  does (ADR 0035). The versions have no policy: the function reads the
  record that decides first, with the options of the caller, and returns
  nothing when the caller cannot read it. `Rescord.History.changes/1` says
  what the versions mean.
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
| `platform/lib/rescord/journal/` | the journal entries and the facts of each medical kind |
| `platform/lib/rescord/history.ex` | reads the versions of a temporal resource as changes, for the timeline |
| `platform/lib/rescord/inventory/` | the items, the lots, the suppliers, the stock movements and the reorder levels |
| `platform/lib/rescord/tasks/` | the tasks, their states and their subjects; the routines, their patterns and the job that makes their tasks |
| `platform/lib/rescord/tenant_migrations.ex` | the repair of a tenant migration (ADR 0025) |
| `platform/lib/rescord/resource.ex` | the base of each resource, and its checks |
| `platform/lib/rescord/rate_limit.ex` | the counts of the rate limits (Hammer, in ETS) |
| `platform/lib/rescord_web/live/` | page LiveViews |
| `platform/lib/rescord_web/widgets/` | live widgets: state, hooks, render |
| `platform/lib/rescord_web/widget.ex` | bookkeeping shared by widgets |
| `platform/lib/rescord_web/components/` | function components and layouts; the parts of the pages of each area (ADR 0037) |
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
| `platform/lib/rescord/release.ex`, `platform/rel/` | the tasks of a release, and its scripts in `bin` (ADR 0044) |
| `platform/Dockerfile`, `deploy/` | the image, the Compose file, and the systemd unit |
| `flake.nix`, `nix/` | the Nix package, the NixOS module and its test |
| `scripts/release-tarball.sh` | the tarballs of the release |
| `docs/self-hosting.md` | the guide for an operator |
| `.github/workflows/` | CI, the flake check, and the release (ADR 0047) |
| `CHANGELOG.md` | the changes of each release, which become its notes |
| `docs/architecture.md`, `docs/adr/` | the design and its decisions |
