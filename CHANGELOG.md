# Changelog

Each change that a person who runs Rescord can notice is in this file,
under the release that has it. The format is
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the
versions follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html):
ADR 0060 says what a major, a minor and a patch mean for Rescord. A release
starts with "Upgrade notes" when an upgrade to it needs a step or a
warning. The release workflow puts the section of a version in the notes of
its GitHub release (ADR 0047).

## [Unreleased]

### Upgrade notes

- The first start of this version runs a migration of each organisation,
  which adds a column to the subjects of the tasks. Make a backup first,
  as `docs/self-hosting.md` says. No new setting is needed.

### Added

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
  comma is refused, because `1,095` can mean two numbers.

### Changed

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

## [0.2.0] - 2026-11-28

### Upgrade notes

- The first start of this version runs a migration of the database, and a
  migration of each organisation for the photos. Make a backup first, as
  `docs/self-hosting.md` says.
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
