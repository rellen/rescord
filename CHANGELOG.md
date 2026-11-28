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

### Added

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
- The groundwork of an assistant with the code name Ruby (ADR 0069). No
  member can use it yet: this version has only the page where a root user
  says which service would answer. Rescord sends nothing to any service
  until a root user adds a provider, and then only the one small question
  of the button "Test", with no record of a rescue in it.
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
  shows no switch. No member can ask Ruby in this version, so the switch
  sends nothing anywhere yet, and the allowance counts nothing yet.
- The page of a provider, for a root user, now says how many
  organisations have Ruby on with it.
- The page of the roles has a new area, "Assistant", with one power: "Ask
  Ruby, the assistant, when the organisation has it on". The role
  Administrator has it after the upgrade. It does nothing in this
  version: it is there for the version in which a member can ask Ruby.
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
  actions take, the background jobs that fail, the emails, and the
  memory. It is off until `RESCORD_METRICS_PORT` names a port. Rescord
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
- The list of the expenses downloads as a CSV file, with the filters of
  the page, for a spreadsheet or for the import of an accounting system.
  The amount is a plain number with the code of its currency beside it.
- The expenses of a period are a new report as PDF, on the page Reports
  and from a link below the list of the expenses: the sums by state and
  by category, what the organisation owes to each member, and the list.
  It holds what the person who makes it can read.
- The lists page has a new list, "Expense category", and the page of the
  roles has a new area, "Expenses", with two powers. The page of a
  resident links to its expenses.
- The export of the data has three new files: `expenses.csv`,
  `expense_receipts.csv` and `expense_categories.csv`. An amount of money
  is two columns, the number and the code of its currency. A person who
  cannot manage the expenses exports only their own. The files of the
  receipts are not in the ZIP.

### Changed

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

### Fixed

- An administrator who removes a resident that was recorded by mistake
  now ends its placement too, and takes the resident out of each task and
  each routine that named it. Before, those records still named a resident
  that was not there. A task that is due and named only that resident is
  skipped, with the reason "The resident was removed", and a member can
  open it again. A task with another resident, a group or a location
  stays due, and a routine goes on for its other residents.

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
