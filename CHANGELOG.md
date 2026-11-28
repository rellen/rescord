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
- A line of the log has more fields than before, between the time and the
  level: the id of the user and of the organisation, and the id, the
  worker, the queue and the try of a background job. A background job
  that fails now writes a line, which is a warning while Rescord tries it
  again and an error after the last try. A tool that reads the log of
  Rescord may need its pattern changed. One new setting is optional:
  `RESCORD_LOG_LEVEL`.

### Added

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
- `RESCORD_LOG_LEVEL` sets how much the log holds: `debug`, `info` (the
  default), `warning` or `error`. `debug` also writes what people type,
  so it is for a short look at a fault.
- Each line of the log now says whose it is: the id of the user and of
  the organisation of a request or a page, and the id, the worker and
  the try of a background job. A background job that fails writes a
  line. `docs/self-hosting.md`, "The log", says what a line holds and
  what it never holds.

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

### Fixed

- An administrator who removes a resident that was recorded by mistake
  now ends its placement too, and takes the resident out of each task and
  each routine that named it. Before, those records still named a resident
  that was not there. The tasks stay due, and a routine goes on for its
  other residents.

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
