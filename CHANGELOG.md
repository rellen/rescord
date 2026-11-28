# Changelog

Each change that a person who runs Rescord can notice is in this file,
under the release that has it. The format is
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the
versions follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
ADR 0060 says what a major, a minor and a patch mean for Rescord. A release
starts with "Upgrade notes" when an upgrade to it needs a step or a
warning. They name each migration that the first start of the release
runs, and say what it does to the data that is there (ADR 0073). The
release workflow puts the section of a version in the notes of its GitHub
release (ADR 0047).

## [Unreleased]

### Upgrade notes

- **Migrations.** The first start of this version runs each of these by
  itself. Make a backup first, as `docs/self-hosting.md` says.
  - `20261127182144_archive_task_subjects`, in each organisation: adds a
    column to the subjects of the tasks. It changes no row.
  - `20261128050845_add_ruby_providers`, in the database: adds the table
    of the providers of the assistant, and the table of their history.
    Both are empty until a root user adds a provider. It changes no row.
  - `20261128050351_add_calendar_feeds`, in each organisation: adds the
    two tables of the calendar feeds, for the feeds and for their
    history. It changes no row.
  - `20261128051000_give_the_first_roles_the_calendar`, in each
    organisation: gives the new power "Subscribe to a calendar feed" to
    the role with the key `administrator` and to the role with the key
    `member`, which are the roles Administrator and Member that each
    organisation starts with. No other row changes: a role that an
    administrator defined does not get the power by itself.
  - `20261128051728_add_the_locale_of_an_organisation`, in the database:
    adds the language and region to the organisations. Each organisation
    that is there gets English (Australia), and no other value of a row
    changes.
  - `20261128054817_add_ruby_conversations`, in each organisation: adds
    the two tables of the conversations with the assistant and of their
    messages. Both stay empty, because no member can ask the assistant
    yet. It changes no row.
  - `20261128055500_give_administrators_the_assistant`, in each
    organisation: gives the new power "Ask Ruby, the assistant, when the
    organisation has it on" to the role with the key `administrator`,
    which is the role Administrator that each organisation starts with.
    No other row changes. The power does nothing in this version.
  - `20261128055107_add_the_strength_of_an_item`, in each organisation:
    adds a column to the items of the inventory, for the strength of a
    medication. It is empty for each item that is there. It changes no
    row.
  - `20261128060812_add_ruby_settings`, in each organisation: adds the
    table of the settings of the assistant, which keeps each version of
    its one row. It is empty after the upgrade, so the assistant is off
    in each organisation until a person there turns it on. It changes no
    row.
  - `20261128054245_install_ash_money_v6_extension`, in the database:
    adds the type of an amount of money, `money_with_currency`, to the
    schema `public`, with its functions, operators and aggregates. It is
    no extension of PostgreSQL. It changes no row.
  - `20261128054252_add_expenses`, in the database: adds the table of
    the shared expense categories, which is empty until a root user adds
    a category. It changes no row.
  - `20261128055627_add_the_currency_of_an_organisation`, in the
    database: adds the currency to the organisations. Each organisation
    that is there gets Australian dollars (`AUD`), and no other value of
    a row changes.
  - `20261128054246_add_expenses`, in each organisation: adds the tables
    of the expense categories, the expenses and their receipts, and the
    two tables of the history of the expenses and the receipts. Each is
    empty. It changes no row.
  - `20261128062000_give_roles_the_expenses`, in each organisation:
    gives the new power "Record an expense with its receipts, and change
    or withdraw their own" to the role with the key `administrator` and
    to the role with the key `member`, and the new power "Read each
    expense, approve or decline one, and record that a member was paid
    back" to the role with the key `administrator`. Those are the roles
    Administrator and Member that each organisation starts with. No
    other row changes: a role that an administrator defined gets neither
    power by itself.
  - `20261128055711_add_episodes`, in each organisation: adds the table
    of the conditions of the residents, which holds its history too, and
    a column to the journal entries, for the condition that an entry is
    about. The table is empty and the column is empty for each entry
    that is there. It changes no row.
  - `20261128065227_add_the_markings_of_a_resident`, in each
    organisation: adds a column to the residents, for the markings of a
    resident. The column is empty for each resident that is there. It
    changes no row.
  - `20261128071744_add_the_tax_name_of_an_organisation`, in the
    database: adds a column to the organisations, for the name of the
    tax that an expense can hold. It is empty for each organisation that
    is there, so no organisation records a tax until an administrator
    names one. It changes no row.
  - `20261128071742_add_the_tax_of_an_expense`, in each organisation:
    adds a column to the expenses, for the tax in the amount. It is
    empty for each expense that is there: Rescord does not work a tax
    out from an amount. It changes no row.
  - `20261128074014_add_ruby_usage`, in each organisation: adds the table
    of the use of the assistant, which holds counts of tokens and their
    price and no word of a conversation, and a column to the messages of
    the conversations. Both are empty after the upgrade, because no
    member can ask the assistant yet. It changes no row.
  - `20261128075805_add_the_paper_size_of_an_organisation`, in the
    database: adds a column to the organisations, for the paper of the
    reports. Each organisation that is there gets A4, which is the paper
    that its reports had, and no other value of a row changes.
  - `20261128080500_add_the_standard_unit_of_a_measure_kind`, in each
    organisation: adds a column to the kinds of measurement, for the
    standard unit of a kind, and fills it for a kind where the answer is
    no guess. A kind that names exactly one unit gets that unit.
    Otherwise, a kind whose measurements all have one and the same unit,
    and none without a unit, gets that unit, when the kind names no unit
    or names that one. Each other kind gets no standard unit. It changes
    no measurement: each keeps the number and the unit that the person
    recorded.
  - `20261128084020_add_the_usage_counts`, in the database: adds the table
    of the usage counts, the table of their settings and the table of the
    history of the settings. All three are empty until Rescord counts. It
    changes no row.
  - `20261128091339_transfer_files_in_a_job`, in the database: adds four
    columns to the transfers, for the files that a job copies after the
    send: their sources, how many there are, how many are copied, and why
    a transfer was not sent. It changes no row: each transfer keeps its
    state, and counts 0 files.
  - `20261128092015_add_correlation_ids`, in the database: adds three
    empty columns, `correlation_id`, `operation_id` and `causation_id`,
    to the 23 tables of the shared records with a history and of the
    histories, for the ids of the work that wrote each version
    (ADR 0101). It has no default. It adds an index on `correlation_id`
    to each of those tables, only for the rows that have one, so each
    index is empty after the upgrade. It changes no row: each version
    that is there keeps no id.
  - `20261128091913_add_correlation_ids`, in each organisation: the same
    three columns and the same index in the 61 tables of the records
    with a history and of the histories. It changes no row.
  - The index is a plain `CREATE INDEX`, because the rehearsal refuses
    `CONCURRENTLY`. It locks each table against reads and writes until
    the migration of its organisation commits. The migrations run at the
    start, before the server answers, so no person waits on a lock, and
    the index reads each row once: on a table of 500,200 rows it took
    about 50 ms. A large organisation starts a little slower one time.
- Before you go back to an earlier version after this upgrade, withdraw
  each transfer that is "Sending" or "Not sent" on the page Transfers of
  its refuge. An earlier version does not know these two states.
- After the upgrade, do not run an older version of Rescord on the
  database, not even for a moment. An older version does not know the
  three new columns: when it changes a record that the new version
  changed, its new version of the record takes the ids of the version
  before, and that one loses them, with no error. The way back stays the
  backup that you made before the upgrade.
- After the upgrade, Rescord counts how often each feature is used on the
  server, and keeps the counts in its database for its root users, at
  `/root/usage`. It sends them nowhere. A root user can turn the counting
  off there, or name an address that gets them (see "Usage counts" in
  `docs/self-hosting.md`).
- Each organisation has the paper A4 for its reports after the upgrade. An
  administrator of a rescue that prints on US Letter changes it on the
  settings page, in "Paper of the reports".
- The first start of this version rehearses the migrations before it
  changes anything, and each later upgrade does the same: it runs each
  migration in a transaction that it takes back, and migrates only when
  each one passed. So the migrations of an upgrade take about two times
  as long as before. When one fails in the rehearsal, Rescord changes
  nothing and does not start, the log names the migration and the
  organisation, and the version that you had still runs on the database,
  with no restore. `docs/self-hosting.md`, "Upgrade", has the steps. The
  backup first stays step 1.
- `RESCORD_KEY_SECRET` now encrypts also the secrets of the settings in
  the database, such as the key of a provider of the assistant. It did so
  for the private keys of the transfers already, so the rule is the same:
  keep a copy of the secret with the backups. A backup of the database
  without this secret cannot open those values.
- After the upgrade, a kind of measurement can have a standard unit, and
  the migration above gave one to each kind where the answer was no
  guess. Rescord now shows each measurement of such a kind in that unit,
  and a new measurement of the kind needs that unit or a unit that
  Rescord converts to it: a measurement with no unit, or in a unit such
  as "bag", is refused. A measurement that is there stays as it is. An
  administrator reads the standard unit of each kind on the page Lists,
  under "Measure kind", and changes it or removes it there. With no
  standard unit, a kind works as in the earlier versions.
- No new setting is needed. One new variable is optional:
  `RESCORD_KEY_SECRET_PREVIOUS` is for the time when you change
  `RESCORD_KEY_SECRET`, and a server that does not change its secret
  does not set it.
- After the upgrade, each person with the role Administrator or Member
  can make a calendar feed, which copies tasks and dates to the calendar
  service of that person. To keep that off, an administrator unticks the
  power "Subscribe to a calendar feed" on the page of the roles.
- The address of a calendar feed holds a secret token in its query. A
  reverse proxy that logs the whole address of each request then holds
  those tokens: see step 5 of the install with systemd in
  `docs/self-hosting.md`.
- Each organisation has the language and region English (Australia)
  after the upgrade, and its pages now write a time of day as `8:30 am`,
  where they wrote `08:30`, and a day as `Monday, 16 November 2026`, with
  a comma. An administrator chooses another one on the settings page:
  English (United Kingdom) has the 24 hour clock, and English (Ireland)
  has exactly the forms of the earlier versions. The exports do not
  change. A build of Rescord from its source needs no network for this:
  the data of each language and region is in the repository.
- A diagnosis that is in a journal before the upgrade starts no condition
  by itself, because the entry does not say if the condition is over. The
  page Conditions is thus empty after the upgrade. In the journal of a
  resident, each such diagnosis has a button "Track this condition", for
  a person who can write journal entries. Nothing must be done: a
  diagnosis that nobody tracks stays as it is, and is in no count.
- A line of the log has more fields than before, between the time and the
  level: the id of the user and of the organisation, and the id, the
  worker, the queue and the try of a background job. A background job
  that fails now writes a line, which is a warning while Rescord tries it
  again and an error after the last try. A tool that reads the log of
  Rescord may need its pattern changed. Two new settings are optional:
  `RESCORD_LOG_LEVEL` and `RESCORD_METRICS_PORT`.
- The role of the database that runs the migrations now makes a type,
  functions, operators and aggregates in the schema `public`, for the
  amounts of money. The owner of the database has that right, so an
  install by `docs/self-hosting.md` needs no step. A server whose role
  does not own the database gives that role `CREATE` on the schema
  `public` before the upgrade.
- Each organisation has the currency Australian dollars after the
  upgrade. An administrator of a refuge with another currency changes it
  on the settings page before the first expense: an expense keeps the
  currency that it was recorded in.
- After the upgrade, each person with the role Administrator or Member
  can record an expense with its receipts, and each administrator reads
  and decides each expense. To keep that off, an administrator unticks
  the powers of the area "Expenses" on the page of the roles.
- The receipts of the expenses are files in the store of the server,
  beside the photos and the attachments, 20 MB each at most. The backup
  of the files holds them.
- Rescord now checks `DATABASE_URL` and `RESCORD_S3_ENDPOINT` at the
  start, and stops with the name of the setting when one is not a URL
  with a host. `DATABASE_URL` takes the schemes `ecto://`, `postgres://`
  and `postgresql://`, and the endpoint takes `http://` and `https://`.
  The message never holds the value, so no password reaches the log.
  Before the upgrade, check that a password in `DATABASE_URL` writes
  each character that a URL may not hold as a `%` code, such as `%20`
  for a space and `%5E` for `^`. A URL that worked before keeps working
  when it has no such character.

### Added

- The members page lists the former members, with the day each one left
  and a button "Invite again", and asks before it removes a member. The
  records of a member who was removed stay theirs: each page names them
  "email (former member)", and the work of a root user who is not a
  member says "Rescord operator". `members.csv` of the export has the
  former members too, with the new column `former?` (ADR 0105).
- A transfer of a resident with photos or PDFs to a partner on this
  server shows "Sending" and how many files are there, such as "120 of
  300 files", while its files go to the partner. When a file does not
  arrive, it shows "Not sent" and why, with the new button "Send again"
  beside "Withdraw". A transfer that is sending or not sent can be
  withdrawn too (ADR 0100).
- For a person who changes Rescord: mutation testing with muex (ADR 0104).
  `mix test.mutation` and the new workflow "Mutation testing" make copies
  of the code with one small change each, and report each change that no
  test notices. The workflow runs each Monday on the lines that changed
  since the last release, and by hand. It never makes a check fail, and the
  release holds none of it: an operator has nothing to do.
- Usage counts (ADR 0098): Rescord counts, for each day, how often each
  feature of the server is used: the pages that open, the actions that
  people run and the files that it sends, with no person, organisation or
  record in a count. A root user reads them on the new page `/root/usage`,
  and chooses there whether the counts stay on the server (the default),
  go each day to one address as OpenTelemetry metrics (OTLP, JSON over
  HTTP) or as a plain JSON document, or are not counted at all. The page
  shows the exact document before anything is sent, and has "Send a
  test". The metrics endpoint has the counter `rescord_usage_count` too.
  `bin/check` says what the server does with them.
- A kind of measurement, such as the weight, can have a standard unit,
  which an administrator chooses on the page Lists. Rescord then shows
  each measurement of that kind in that unit: in the charts and their
  tables, in the journal, in the timeline, on the cage card and in the
  record of a resident. A person can still record another unit that
  Rescord converts, such as kg for the standard unit g, and the journal
  keeps what the person recorded and says it: "610 g (recorded as
  0.61 kg)". The forms choose the standard unit when a person chooses
  what was measured (ADR 0094).
- The file `measurements.csv` of the export has two new columns at its
  end, `standard_value` and `standard_unit`: the measurement in the
  standard unit of its kind, with no rounding. The columns `value` and
  `unit_id` stay as the person recorded them (ADR 0094).
- Rescord now has a colophon, at `/colophon`: what Rescord is, its
  licence, what it is built with, how its pages are made, and an
  accessibility statement that says what is tested and what is not right
  yet. Each page now ends with a footer that links to the colophon, to
  the accessibility statement and to the source code. A person who is
  signed in also reads the version of Rescord there (ADR 0090).
- The page of an error, such as an address that Rescord does not have,
  is now a page of Rescord: it has the look of the site, a heading, words
  that say what to do, and a link to the first page. Before, it was the
  two words "Not Found" (ADR 0090).
- The new command `bin/check-files` (`rescord-check-files` on NixOS)
  compares the files of the store with the records of the database
  (ADR 0091). An upload or a transfer that fails after it put a file in
  the store leaves that file there, and no record names it. Until now
  nothing counted those leftovers. The command says how many files a
  record names, how many are leftovers and how much space they take, and
  it names each file that a record names and that the store does not
  have, with the kind of the record, its id and its organisation. It
  changes nothing: it deletes no file. It exits with 1 when a file is
  missing, and with 0 for leftovers alone. `docs/self-hosting.md` has
  the section "Check the files".
- Rescord now records the conditions that a resident has, such as
  bumblefoot or a respiratory infection, each with its first day, its last
  day when it is over, a mark for a chronic condition and a note
  (ADR 0083). A journal entry of the kind diagnosis starts a condition, or
  joins the one that the resident has now. A member marks a condition as
  resolved, opens it again, or changes it, and an administrator removes
  one that was a mistake.
- A journal entry can say which condition of the resident it is about.
  The journal of a resident has a link for each condition, which shows
  the entries about it, and the page of a resident shows what the
  resident has now. The timeline says when a condition was resolved.
- The new page Conditions, from the list of the residents, counts what
  the residents in care have now, by condition and by where they live,
  and how many conditions started in each of the last 3, 6, 12 or 24
  months. It lists each condition of each resident, with a search and
  filters by condition, state and first day.
- The copy of a resident in a transfer now holds the conditions of the
  resident, and the export of the data has the file `episodes.csv` and the
  column `episode_id` in `journal_entries.csv`.
- A start rehearses an upgrade before it changes anything (ADR 0081).
  Until now a migration that failed on the data of one organisation left
  the server half migrated, and only a backup went back. Now each
  migration that has not run, of the database and of each organisation,
  first runs in a transaction that Rescord takes back. When each one
  passed, the migrations run. When one failed, nothing is changed, and
  the log says which migration failed in which organisation, with the
  message of PostgreSQL and without the values of a row.
  `bin/migrate --rehearse` rehearses and changes nothing, to try a new
  version before the day of the upgrade, and `bin/migrate --no-rehearsal`
  is for a release whose upgrade notes ask for it. The NixOS module
  installs `rescord-migrate`.
- A resident has a page "Measurements", which shows each kind of
  measurement over time: the newest value, its change from the one
  before, a chart, and each value in a table. A member chooses the last
  30 days, 90 days, a year, or each measurement, presses a point of a
  chart to read it, and records a new measurement on the same page. A
  measurement in another unit that Rescord knows, such as kg beside g, is
  in the same chart. The page says how many measurements are not in a
  chart because their unit does not convert (ADR 0080).
- A group has a page "Measurements", with one kind of measurement for
  each member, such as the weights of a litter: a small chart for each
  member, on one scale, with the others behind it.
- The page of a resident shows a small chart and the change beside the
  newest value of each kind of measurement.
- The charts are drawn by the server, with no script and no service of
  another host. Each chart has a description for a screen reader, and its
  values as a table.
- An assistant with the code name Ruby (ADR 0069), which a member asks
  about the records of the rescue. Rescord sends nothing to any service
  until a root user adds a provider: then the one small question of the
  button "Test", with no record of a rescue in it, and the questions of
  the members of an organisation that turned Ruby on.
- A root user has a new page, `/root/ruby`, with the providers of the
  assistant: Anthropic, Amazon Bedrock, Ollama, or a server that speaks
  the chat API of OpenAI. A provider has a name, a model, a key and
  limits. Rescord keeps the key encrypted, and no page shows it again:
  only its last four characters and the day that it was set. The history
  of a provider holds each change, without the key. The assistant reads no
  variable of the environment.
- An organisation has a new page, "The settings of Ruby", which the
  settings page links to for a person whose role has the power "Change
  the settings of the organisation". It shows, in a sentence, where the
  records of a question would go with the service that the server
  offers, and has the switch that turns Ruby on for the organisation,
  the allowance of a month in US dollars and the days that a
  conversation is kept. Who turns Ruby on agrees to that place, and
  Rescord keeps the sentence and the time. When a root user changes the
  address or the region of a provider, or stops offering it, Ruby is off
  for each organisation that agreed to the old place, until a person
  there reads the new one and agrees. A server with no offered provider
  shows no switch. The allowance counts the cost of each answer.
- The page of a provider, for a root user, now says how many
  organisations have Ruby on with it.
- The page of the roles has a new area, "Assistant", with one power: "Ask
  Ruby, the assistant, when the organisation has it on". The role
  Administrator has it after the upgrade.
- A member whose role has the power "Ask Ruby" asks Ruby on a new page,
  `/o/<organisation>/ruby`, while the organisation has Ruby on. The page
  offers a few things to ask, keeps the conversations of the member, and
  shows the words of the answer as they arrive, with a button Stop. Ruby
  reads only what the member can read, and records nothing. The page has
  no link in the menu yet: that comes in a later version. For anybody
  else, or while Ruby is off, the address is a page that is not there.
- `bin/rotate-vault` (`rescord-rotate-vault` on NixOS) encrypts again each
  value that `RESCORD_KEY_SECRET` guards, after you change the secret:
  the secrets of the settings and the private keys of the transfers.
  `docs/self-hosting.md` has the steps, in "Change the secret of the
  keys". Before this version a server could not change that secret.
- `bin/check` has two new lines. `vault` says whether each encrypted
  value opens with the secret of the server. `assistant` has a line for
  each provider: where the records would go, and what its last test
  found. Neither sends a request, and neither prints a key.
- An organisation now has a language and region, which say how its pages
  write a date, a time of day and a number: `16 November 2026` and
  `6:30 pm` for English (Australia), `November 16, 2026` and `6:30 PM`
  for English (United States), `18:30` for English (United Kingdom). A
  root user chooses it when they create the organisation, and an
  administrator changes it on the settings page, which shows an example
  of each form. There are nine to choose from, each an English of a
  region: Australia, Canada, India, Ireland, New Zealand, South Africa,
  the United Kingdom, the United States, and the world. The words of the
  pages are English in each one.
- Rescord now makes reports as PDF, for paper. The new page Reports, in
  the site menu, has the register of the residents in care on a day, the
  arrivals and the departures of a period with their totals, the tasks of
  a day with a box to tick for each, the stock with a column for a count,
  and the housing with who lives where. The page of a resident has its
  record, with its medical history or its whole journal and its photos on
  request, and a cage card for the door of its pen. Each member can make
  each report, and a report holds what that member can read. A report
  opens in the browser, which prints it or saves it. The release now
  carries the Typst compiler, about 73 MB, and needs no new setting
  (ADR 0076).
- A report is on A4 or on US Letter (ADR 0093). The settings page has the
  new part "Paper of the reports", where an administrator chooses the
  paper of the organisation: A4 at first. The page Reports and the part
  "On paper" of the page of a resident have a control "Paper", with the
  paper of the organisation chosen, so a person can make one document on
  the other paper. The address of a report takes `paper=a4` or
  `paper=us_letter`.
- Rescord now knows what a unit of measure means, from its name. The
  lists page says for each unit of an organisation, and for each shared
  unit, whether Rescord can convert it: `kg` is a kilogram, a mass, and
  `bag` is a name of the organisation that Rescord does not convert. The
  units that it knows are those of a mass (mcg, mg, g, kg, oz, lb), a
  volume (mL, L), a length, a temperature, a time and an energy, the
  tablet, the capsule, the drop and the international unit, with names
  such as `Kilograms` and `millilitre` too. Nothing in the records
  changes, and a unit that Rescord does not know works as before. This is
  the base of the dosage calculator, which comes next.
- An organisation now has tools, as a new part of the site menu, and the
  first tool is a dose calculator. A member types the weight of an animal
  (in kg, g, lb or oz), the dose rate for each kilogram (in mg, mcg, g or
  mL), and, for a volume or a number of tablets, the strength of the
  product. The page gives the dose and the amount of the product, shows
  each step of the arithmetic, and says to check the result with a vet. It
  knows no medication: it offers no dose rate and does not say that a dose
  is safe. It stores nothing, and each member can use it. A number with a
  comma is refused, because `1,095` can mean two numbers. The weight can
  come from the journal of a resident: the member chooses the resident, or
  presses "Calculate a dose" on the page of the resident, and the
  calculator says the date of that measurement and how many days ago it
  was.
- An item of the inventory can have the strength of a medication, such as
  1.5 mg in each mL or 50 mg in each tablet. An administrator writes it in
  the form of the item, from the label. The dose calculator offers the
  items that have a strength and fills it in, says which item it read, and
  says when the records have no stock of that item that is in date. The
  page of such an item has the link "Calculate a dose with this strength".
  The export of the data has the strength in the file of the items.
- Calendar feeds. A member makes a feed on the new page "Calendar feeds",
  and subscribes to it in a calendar app such as Apple Calendar, Google
  Calendar or Outlook. The feed holds the tasks that the member chooses:
  the tasks that name them, those and the tasks for anybody, or each
  task. It can also hold the days on which residents are expected back,
  and the expiry dates of the stock. The calendar app only reads: each
  event links to its record in Rescord. The address of a feed is a secret
  that the page shows one time, and a member revokes a feed at any time.
  A person who can invite and remove members sees who has a feed, and
  when a calendar app last read it, and can revoke it. The notes that
  people wrote are in a feed only when the member asks for them.
- Rescord can give metrics about itself to a collector such as
  Prometheus: how long the requests, the pages, the queries and the
  actions take, the background jobs that fail, the emails, the replies
  of the assistant with their tokens, and the memory. It is off until
  `RESCORD_METRICS_PORT` names a port. Rescord
  then answers `GET /metrics` on that port, which is not the port of the
  pages and has no sign-in, so keep it inside the network of the server.
  No label holds the id of a person or the name of an organisation.
  `docs/self-hosting.md`, "The metrics", has the steps.
- `RESCORD_LOG_LEVEL` sets how much the log holds: `debug`, `info` (the
  default), `warning` or `error`. `debug` also writes what people type,
  so it is for a short look at a fault.
- Each line of the log now says whose it is: the id of the user and of
  the organisation of a request or a page, and the id, the worker and
  the try of a background job. A background job that fails writes a
  line. `docs/self-hosting.md`, "The log", says what a line holds and
  what it never holds.
- An organisation now records its expenses (ADR 0082). Rescord is not an
  accounting system: it records what was paid, keeps the receipt, gets a
  decision, and remembers that a member was paid back. The new page
  Expenses, in the site menu, has the list with a search and filters, and
  three sums at its top: what waits for a decision, what is to pay back,
  and what was spent this month.
- A member records an expense that they paid, or that the organisation
  paid: the amount, the date, who was paid, what it was for, a category,
  the resident that it was for, a note, and its receipts, each a photo
  or a PDF. Rescord removes the metadata of a photo of a receipt, the
  place with the rest.
- A person with the new power to manage expenses approves an expense or
  declines it with a reason, records the day and the reference of the
  payment back to the member, and can open a decision again. A member
  reads only their own expenses, changes one until somebody decides, and
  sends a declined one again. The page of an expense shows what happened
  to it, the newest first.
- An organisation has a currency, Australian dollars at first, that an
  administrator changes on the settings page. A page writes an amount in
  the language and region of the organisation, such as `$1,234.50`.
  Rescord converts no amount: expenses in two currencies have two sums.
- An expense can hold the tax that is in its amount, such as GST or VAT
  (ADR 0089). An administrator gives the name of the tax on the settings
  page, and the form of an expense then has the optional field, for
  example "GST in the amount". A person copies the tax from the receipt:
  Rescord knows no rate and no tax code, and the amount stays the whole
  amount. A person who manages the expenses corrects the tax of an
  expense in each state, also after the decision. With no name of a tax,
  the expenses record none.
- The list of the expenses downloads as a CSV file, with the filters of
  the page, for a spreadsheet or for the import of an accounting system.
  The amount is a plain number with the code of its currency beside it,
  and the tax in the amount has a column of its own.
- The expenses of a period are a new report as PDF, on the page Reports
  and from a link below the list of the expenses: the sums by state and
  by category, what the organisation owes to each member, and the list.
  It holds what the person who makes it can read. When the organisation
  names a tax, the report has the tax of each expense and of each sum.
- The lists page has a new list, "Expense category", and the page of the
  roles has a new area, "Expenses", with two powers. The page of a
  resident links to its expenses.
- The export of the data has three new files: `expenses.csv`,
  `expense_receipts.csv` and `expense_categories.csv`. An amount of money
  is two columns, the number and the code of its currency. A person who
  cannot manage the expenses exports only their own. The files of the
  receipts are not in the ZIP.
- A resident can have markings: free text, at most 300 characters, for
  what tells it apart and is in no list, such as a torn ear or a white
  blaze on the nose (ADR 0085). It is for the many residents that carry no
  microchip and no ear tag. The form of a resident has the field, and no
  resident needs it. The page of a resident, the cage card, the record of
  a resident and the copy of a transfer show the markings when a resident
  has them, and have no row for them when it has none. The search of the
  residents page finds a resident by its name or by its markings.
  `residents.csv` of the export has the new column `markings`.
- Each version that Rescord writes in a history now holds three ids
  (ADR 0101). `correlation_id` is the same for each version of one piece
  of work: the removal of a resident, with the tasks and routines that it
  changes, has one. `operation_id` is the id of the one action that wrote
  the version, and `causation_id` is the `operation_id` of the action
  that ran it, so the versions of one piece of work make a tree. A
  version from before the upgrade has none. No page shows them yet; a
  person who runs a server can find each version of one piece of work
  with a query on `correlation_id`.

### Changed

- The removal of a member takes them out of each task that is due and
  each routine. A task that was for them alone is for anybody. Their
  calendar feeds are revoked, and an invitation of theirs that waits is
  not sent. The last member who can change the members cannot be removed
  (ADR 0105).
- A line of the log now writes the shape of a value with
  `Shoddy.Terms.shape/2` of `shoddy`, and Rescord no longer has its own
  copy. A tuple of more than 6 values now shows each value, an Ash error
  inside another failure names its errors, and the field `:fields` of an
  error no longer shows. The line still holds no data of a person (ADR
  0077).
- The send of a transfer to a partner on this server no longer copies
  the photos and the PDFs of the copy: it returns at once, and a
  background job copies them, one at a time, in the new queue of Oban
  `transfers`. The partner sees the transfer when each file is there. A
  fault of the store no longer takes back the whole send: the job tries
  again from where it stopped, 10 times in about 20 minutes, and then the
  transfer is "Not sent" (ADR 0100, issue 16).
- The pages have icons of our own beside the words: each part of the
  site has one shape in the menu, on the page of the organisation, in
  the parts that need attention, in the reports and on the heading of
  its page, and each kind of journal entry has one in the journal, the
  timeline and the copy of a transfer. "Profile picture" is a label with
  a star, and no longer a state with a clock. The common actions (add,
  change, remove, end, undo, download, upload), the figures of the
  expenses, the history of the stock and the headings of the settings
  have icons too, and the arrows of the tables are line chevrons in
  place of solid triangles. Words still say what each icon means, and a
  screen reader does not read the icons (ADR 0102).
- A failure of Rescord itself, such as a time after now in a form, a
  file that is not a photo or an email of an invitation that the mail
  server refused, is now an error with a name and a reason, and no
  longer a sentence. The log line of a background job that fails names
  that error and its reason, such as
  `Rescord.Accounts.Errors.InvitationNotSent`, where it said only that
  the reason was text. The words on the pages are the same (ADR 0077).
- The site menu, the list of the parts on the first page of an
  organisation, and the other links from one live page to another now
  move over the open connection, with no load of a document. A move is
  quicker, and the server reads the new page once and not twice
  (ADR 0099).
- The chart of a kind of measurement with a standard unit is in that
  unit. It was in the unit of the newest measurement, so one weight in
  kg changed a chart in g. A kind with no standard unit keeps the unit of
  its newest measurement (ADR 0094).
- A new measurement of a kind with a standard unit needs a unit: that
  unit, or one that Rescord converts to it. The form has no choice "No
  unit" for such a kind (ADR 0094).
- The title of each page, which the tab of the browser shows, now has
  the name of the page first and the name of the site after it:
  "Residents · Rescord". The sign-in pages, which all had the title
  "Rescord", now have a title each (ADR 0090).
- The bar that shows that a page loads is now drawn by the stylesheet,
  and it does not move for a person whose device asks for less motion
  (ADR 0090).
- When a member records that a resident left, Rescord now ends the
  placement of the resident, and takes it out of each routine and of each
  task that is due. A task that named only that resident is skipped, with
  the reason "The resident left", and a member can open it again. A task
  that is done keeps the resident. Before, a resident that left kept its
  place in the housing, its tasks stayed due, and its routines made more.
  A departure that a member withdraws restores none of this: place the
  resident again, and add it to its routines again. A resident that left
  before this version keeps its place and its tasks until a member clears
  them.
- Five pages show what another person did, without a reload: the first
  page of an organisation, the tasks, the transfers, the partner refuges
  and the expenses. A task that another member takes or finishes, a
  transfer that arrives, the answer of the other refuge and a decision
  on an expense show at once. The first page still reads each minute
  too, for a task that becomes overdue (ADR 0096).
  An instance on several machines shows such a change on each machine
  only when the machines form a cluster (`DNS_CLUSTER_QUERY`); with no
  cluster the pages on another machine are as before.
- The upgrade notes of a release now name each migration that the first
  start runs: whether it runs in the database or in each organisation,
  what it does to the rows that are there, and each step by hand in full,
  with the query that finds the rows. A check fails for a migration with
  no note, at each push and before a release (ADR 0073).
  `docs/self-hosting.md`, "Upgrade", says how to read the notes, and
  `docs/migrations.md` holds the rules for a person who changes the
  database of Rescord.
- The first page of an organisation now says what needs attention: the
  tasks that are overdue or due today, the items to count or to order and
  the stock that is past its expiry date or expires soon, the residents
  that are late back or expected, the locations over their capacity, and
  the transfers and partner requests that wait for an answer. Each row
  opens the page where a member acts on it. A person sees only what their
  role can act on, and the page reads again each minute. The links to
  each part of the organisation are below it.
- A background job now sends the email of an invitation, after the
  invitation is saved. When the mail server does not answer, Rescord sends
  the email again, with a longer wait before each try, for about 18 hours.
  Before, a fault of the mail server lost the email, and only the log said
  so. The person who invites sees the new member at once, as before.
- The emails of Rescord now have an HTML part with the look of the
  application: the email with a sign-in link, the invitation to an
  organisation, and the test email of `bin/check`. Each one follows the
  light or the dark scheme of a mail program that states it, has a button
  for its one action, and loads no image and no font, so a mail program
  has nothing to block. Each one keeps a text part with the same words,
  for a program that shows plain text. The mail settings do not change.
- A resident needs no identifier, and a page or a report no longer has an
  empty place for one: many species, guinea pigs among them, carry no
  microchip and no ear tag. The page of a resident has no sentence "No
  identifier is recorded", and it has the section of the identifiers only
  when the resident has one or the person can add one. An organisation
  that uses no identifier retires each identifier kind on its lists page,
  and the section then shows only on a resident that has one. The register
  on paper has its column of identifiers only when a resident of the
  register has one.
- The list of the residents, the members of an organisation and the
  organisations of the root page now keep their search, their filters,
  their sort and their page in the address. A person who opens a record
  and goes back finds the list as it was, and the address of a filtered
  list can be kept or sent. The residents also have a filter on the
  species and a choice of 25, 50 or 100 on a page. The members have a
  search on the email address and a filter on the role. Each list says
  when nothing matches the filters, and when there is nothing yet
  (ADR 0084).
- The page of an item of the inventory now shows each stock movement of
  the item, in pages of 25, 50 or 100, with a filter on the date, on the
  kind of movement and on the lot, and a sort on the time. Before, it
  showed the newest 100 movements and had no way to the older ones
  (ADR 0084).
- The inventory page now has a search on the name of an item, a filter
  on the category, and a filter on the state of the stock: each item
  that needs attention, or only the items below a reorder level, with
  stock past its expiry date, with stock that expires soon, or below
  zero. The items are in pages of 25, 50 or 100, and the address holds
  the search and the filters, so the address that ends in `?state=short`
  is the list of what to order. The page also reads less: the stock
  movements of the items that it shows, and not of each item
  (ADR 0088).
- The journal of a resident now shows 25, 50 or 100 entries on a page,
  the newest first, with a search and filters: a text of a note, of a
  medication, of a vaccine or of a dose; the kind of the entry; and the
  dates between which a thing happened. "The medical history" is one of
  the filters, and its address, which ends in `?only=medical`, is the
  same as before. The two links in the header that did this are gone.
  The address holds the search and the filters, and a link to another
  condition keeps them. A link from the measurements or from a photo to
  its entry now opens that one entry, with what a member added to it
  (ADR 0092).
- The tasks page now has a search on the title of a task, and filters on
  the state (due, done or skipped), on the kind, and on who does it: "Me",
  "Anybody" for the tasks that name no member, or one member. The tasks
  are in pages of 50, 100 or 200. The address holds the search and the
  filters, so the address that ends in `?state=due&who=me` is what is left
  for the person who opens it, and "The day before" and "The day after"
  keep them. On today the tasks of earlier days that are still due are
  now at the top of one list, each with its day, and not in a table of
  their own, so a filter holds for both. After Take, Done, Skip or Open
  again the page stays where it was (ADR 0097).

### Fixed

- The table "Owed to members" of the expense report put every person who
  had left in one row "A person who left". Each payer has their own row
  now (ADR 0105).
- The name of a location now keeps its capitals where it starts a line of
  the inventory: in the levels of a lot, the history of an item, the
  reorder levels and the stock to order. Before, only its first letter
  stayed a capital, so "ICU ward B" read "Icu ward b".
- The focus of the keyboard now stays where a person works. After a
  press on a button that then goes, such as Done of a task, the focus
  stays in the same row. After a link to another page, the focus goes to
  the heading of the new page, which a screen reader then reads. Before,
  the focus went to the top of the page each time (ADR 0090).
- A receipt that is a file, and not a picture, is now a link with a name
  for a screen reader: the name of the file and its kind. Before, the
  link had no name (ADR 0090).
- The name that a screen reader and voice control get for a button now
  starts with the words that show on the button, so a person who says
  "Take off" or "Pause" to the device reaches it. This is so for the
  buttons of the receipts, the attachments, the photos, the routines,
  the tasks, the families and the root users (ADR 0090).
- An administrator who removes a resident that was recorded by mistake
  now ends its placement too, and takes the resident out of each task and
  each routine that named it. Before, those records still named a resident
  that was not there. A task that is due and named only that resident is
  skipped, with the reason "The resident was removed", and a member can
  open it again. A task with another resident, a group or a location
  stays due, and a routine goes on for its other residents.
- The filters and the pages of a list now work with a keyboard and a
  screen reader. The button of a filter with choices says its choice
  and if its list is open. The arrow keys move through the choices, and
  Enter or Escape closes the list. Before, the list closed at each
  press and the focus went to the top of the page. The buttons that
  clear a filter and that change the page have words for their names,
  the pages are a landmark, a table has a name, and a screen reader
  says the new count after a filter or a search (ADR 0087).

### Security

- The history of a record is closed to each request that asks for it by
  itself. Rescord keeps each change of a record as a version, and the
  versions had no rule of their own about who reads them. A page shows the
  history of a resident only after the resident has passed the rules of
  the role of the person, and that stays so. No page read the versions
  another way: this closes the gap before a page or an interface could use
  it. No step is needed at the upgrade.
- The log no longer holds what a person typed when a page stops with a
  fault. Before, the line of such a fault held the last message of the
  page: the fields of the form that the person had sent, or a record
  that the page was told about. Now it holds the shape of that message,
  and still the function and the line of the fault. Two lines of the log
  about the routines, and the page of the export, could show the message
  of an error, which can name a value of a record. They now name the
  kind of the error. A log from before this version can hold such lines:
  keep it as private as the database, or delete it. No step is needed at
  the upgrade.

## [0.2.0] - 2026-11-28

### Upgrade notes

- **Migrations.** The first start of this version runs each of these by
  itself. Make a backup first, as `docs/self-hosting.md` says. These
  notes first said "a migration of the database": this release has none.
  - `20261125120000_give_administrators_the_export`, in each
    organisation: gives the role of the administrators the power
    `export`, for the export of the data. No other row changes.
  - `20261126230812_photos`, in each organisation: adds the tables of the
    photos, the albums and the profile pictures, and a column for the
    thumbnail of a file of the journal. It changes no row.
- No new setting is needed. `RESCORD_PHOTO_SLOTS` and
  `RESCORD_BACKUP_KEEP_DAYS` are new, and each has a default.
- To get the backups of each day: with Docker Compose, take the new
  `compose.yaml` and `backup.sh` of `deploy/compose`; from the tarball,
  install the two units `rescord-backup` of `deploy/systemd`. The NixOS
  module turns them on by itself. `docs/self-hosting.md`, "Back up", has
  the steps.

### Added

- `bin/move-storage disk s3`, or `s3 disk`, copies the files of a server
  from its directory into a bucket of S3, or back, for a server that
  changes `RESCORD_STORAGE`. It reads each copy back and compares it,
  copies only what is missing when it runs again, and deletes nothing.
  `docs/self-hosting.md` has the steps.
- The tab of a browser shows the mark of Rescord, in the colour of the
  light or of the dark scheme, and a home screen shows it too.
- A transfer of a resident can carry its photos, its albums and its
  profile picture, as a part that the sender ticks, on one server and in a
  transfer file. The refuge that receives sees them on the page of the
  copy.
- Each resident has photos, with a caption and a date, in albums, and a
  profile picture that its page and the list of the residents show. The
  photos of its journal entries are among them, with a link to each entry.
  Rescord removes the metadata of each photo, the GPS position with the
  rest, turns it as the camera recorded, and makes a thumbnail, with
  libvips through the package `image`. A photo attached to a journal entry
  gets the same treatment. Rescord works on two photos at the same time,
  and the others wait for their turn, so a batch of large photos does not
  fill the memory of a small server. `RESCORD_PHOTO_SLOTS` sets the number.
- An administrator exports the data of an organisation as one ZIP of CSV
  files, as it stood at the end of a chosen day, with a README. The power
  `export` can go to another role.
- `bin/check` says whether a server is ready: the database, the
  migrations, the store, the SMTP server, and a test email.
- Backups each day in each way of installing, and `bin/restore` to put one
  back.
- `bin/check` and the page of a root user say which version of Rescord the
  server runs.

### Changed

- Rescord is mobile first (ADR 0061). On a phone the site menu is one bar
  with the button "Menu", which opens the menu below it, and the bar stays
  at the top of the screen. The menu took five lines of each page before.
  On a wide screen the menu is two rows: the name of the site and the
  account, then the parts of the organisation, so a long email address no
  longer wraps it. The menu marks the part that the page is in. A field
  for a number asks a phone for its keyboard of digits.
- On a phone each row of a table is a card, with the name of the column
  before each value, and no page scrolls sideways at a width of 320px.
  Each button, field, summary and tick box is 44px high or more, on each
  screen, and the text of a field is 16px, so Safari on a phone does not
  make the page larger at a focus. The photos of a resident are two
  columns on a phone, a flash message is at the foot of the screen there,
  and the button of a form is as wide as the form.
- The versions of Rescord follow Semantic Versioning, and this file follows
  Keep a Changelog, with the notes of an upgrade first (ADR 0060). A
  release now runs the tests too, before it publishes anything.
- Each release now tests an upgrade from the last release, with its data,
  before it publishes anything.
- CI fails on a dependency with a security advisory, and Dependabot
  proposes updates each week.
- The dependencies are at their newest versions of 24 November 2026:
  Ash 3.38, Phoenix LiveView 1.2.15, Postgrex 0.23, PostgreSQL 18.7, and
  Debian 13 of 23 November 2026 in the image.

### Security

- Phoenix LiveView 1.2.14. In 1.2.13, a join of a page without a URL
  skipped the `on_mount` hooks of its `live_session`, which find the member
  and the role on the pages of an organisation.
- Erlang/OTP 29.1.3 in the image, the tarball and the Nix package, for nine
  CVEs, three of them in `binary_to_term`. db_connection 2.10.3 for
  EEF-CVE-2026-133555, and Ash 3.38.1 for EEF-CVE-2026-120299, which
  Rescord did not reach.

## [0.1.0] - 2026-11-20

The first release, for a rescue that runs Rescord on a server of its own.

### Added

- The sign-in by a link in an email, with no password. A link works one
  time, the answer to a request does not say whether an address has an
  account, and each address and each client has a limit.
- A root user, made by a command when Rescord is first deployed. A root user
  makes organisations and invites their administrators, and an administrator
  invites the members.
- Each organisation keeps its data in a schema of its own, and defines its
  roles, with the powers of each.
- The residents, with their history: names, breeds, colours, temperaments,
  desex status, families and groups.
- The housing as a tree of locations, and the placement of each resident or
  group.
- The journal of each resident, with medical entries, and photos and PDFs
  attached to an entry.
- The tasks and the routines that make them, and the inventory: items, lots,
  suppliers, stock movements, units and reorder levels.
- The timeline of a resident.
- Transfers of a resident between partner refuges, on one server or between
  two servers by a signed and encrypted file.
- A Docker image for amd64 and arm64, with a Compose file of PostgreSQL 18,
  Rescord and Caddy.
- A Nix flake with a package and a NixOS module.
- A tarball for amd64 and arm64, with a systemd unit.
- The mail goes through any SMTP server, and the files go to a directory or
  to a service that is compatible with S3, with the bucket in the path or
  in the host.
- Rescord counts the limits of the sign-in by the address of the client
  behind a trusted reverse proxy.
- `docs/self-hosting.md` lists each setting, and says how to back up and
  upgrade.

[Unreleased]: https://github.com/rellen/rescord/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rellen/rescord/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rellen/rescord/releases/tag/v0.1.0
