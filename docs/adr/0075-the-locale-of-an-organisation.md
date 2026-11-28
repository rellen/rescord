# ADR 0075: The locale of an organisation, with Localize and not yet AshLocalize

Status: accepted. The maintainer asked on 28 November 2026 whether
Rescord can use AshLocalize, and chose "Localize now, AshLocalize later"
from the design (issue 8). It follows ADR 0026 (the time zone of an
organisation) and ADR 0068 (a setting is a resource).

## Context

The pages are in English. A date was `16 November 2026`, a time of day
was `08:30` and a number was `1,095`, for each organisation, from six
functions with `Calendar.strftime` and one regular expression. A refuge
in the United States writes `November 16, 2026`, and Rescord had no
setting for that.

[AshLocalize](https://github.com/elixir-localize/ash_localize) is the Ash
layer over [Localize](https://hex.pm/packages/localize), the library for
the data of CLDR that follows `ex_cldr`. It has Ash types that check a
code (a locale, a territory, a time zone, a currency), a `format/2` and
calculations for a date, a number, a list, money and a unit, a function
that writes the numbers inside an Ash error in the form of a locale,
types for units of measure, and types for a name, a phone number and an
address.

Its state on 28 November 2026:

- It is not on Hex. `mix.exs` says 0.1.0, with no tag. It has 46 commits
  by one author, from 22 May 2026 to 2 August 2026, and none since. Its
  README says "early development", and its plan says that nothing is
  locked.
- Translated content of a record, the plug and the form inputs for
  Phoenix, and the types for PostgreSQL are in its plan, and are not
  built.
- It compiles and runs inside Rescord, with Ash 3.38.1 and Localize
  1.11.0, pinned to its newest commit.
- Its `mix.exs` looks for libphonenumber and libpostal on the machine and
  declares more dependencies when it finds them, and it writes a file
  into its own directory when Mix loads it.

Localize itself is on Hex: 1.0 on 31 July 2026, 1.11.0 on 27 November
2026, about 400,000 downloads, under Apache-2.0 with the data under
Unicode-3.0. For Rescord it is one new package, with no native code.

## Decision

### AshLocalize waits for a release

Rescord does not depend on AshLocalize now.

- A package with no release is a pin to a commit. `mix hex.audit` and the
  weekly update of the dependencies (ADR 0048) do not see it, and its
  interface can change.
- What Rescord would use is small: the type of a locale (28 lines), a
  `format/2` of 10 lines over a protocol of Localize, and the rule for
  which locale applies. Rescord has no API, so the calculations give it
  little.
- The parts that would be worth a dependency are the ones that are not
  built.
- The units of measure of Rescord are not the unit types of AshLocalize.
  A dose needs units that CLDR does not have, such as a tablet, and keeps
  the unit that the person wrote (ADR 0071). A quantity writes its number
  with `JournalWords.number/1`, so it has the form of the locale too.

Look again when AshLocalize has a release on Hex, or when Rescord needs a
phone number or a postal address as a type, or translated content. The
step is small then: an organisation stores its locale as a tag of BCP 47,
which is what the type `:locale` of AshLocalize stores.

### An organisation has a locale

- The attribute `locale` of an organisation is a tag of BCP 47, such as
  `en-AU`. It is necessary. The default is `en-AU`, for a new
  organisation and for each one that exists at the upgrade.
- **Rescord offers a fixed list**, `Rescord.Accounts.locales/0`: the
  English of Australia, Canada, India, Ireland, New Zealand, South
  Africa, the United Kingdom, the United States, and of the world
  (`en-001`). The words of a page are English, so each locale is the
  English of a region. A translation of the pages would add languages to
  this list. It is not part of this record.
- A locale is valid when it is in the list
  (`Rescord.Accounts.locale?/1`). Localize accepts a tag that it has no
  data for, so its own check is not enough.
- A root user chooses the locale when they create the organisation. An
  administrator, and a root user, change it on the settings page, under
  "Language and region", through the action `set_locale` and the grant
  `{Organisation, :set_locale, :all}` of the power `settings`. A member
  reads it. This is the pattern of the time zone.
- The locale is of the organisation, and not of a user: the record of an
  animal belongs to the organisation, and its members read the same page.

### One module writes the forms

- **`RescordWeb.Locale` is the one module that calls Localize.** It has
  `date/1`, `day/1`, `time/1`, `date_time/1` and `number/1`.
- `put/1` sets the locale of the process, and the hook
  `:require_organisation` calls it with the organisation of the page.
  `current/0` reads it. A process with no locale has the default. The
  locale of a process does not reach a task that the process starts: a
  task gets the tag, and calls `put/1`.
- Each function gives Localize the locale by name. The default locale of
  Localize can come from the variable `LANG` of the server, so Rescord
  does not rely on it, and `config :localize` names a default too.
- The functions that a page calls keep their names:
  `ResidentWords.date/1`, `TaskWords.day/1`, `TaskWords.time/1`,
  `JournalWords.time/1` and `JournalWords.number/1` call
  `RescordWeb.Locale`.
- **`number/1` never rounds.** The default pattern of a locale keeps
  three digits after the point: Localize writes `0.00025` as `0`. Rescord
  shows doses and measurements, so `number/1` asks for each digit of the
  value.
- `time/1` writes a usual space where CLDR has a narrow no-break space
  (U+202F) before `am`, so a search of the page and a test find
  `8:30 am`.
- A date with a time is the date, a comma and the time:
  `16 November 2026, 8:30 am`. CLDR would write "at" between them.
- When Localize gives an error, a function writes the ISO form or the
  plain digits, and logs a warning. A page does not fail for a form.

### The files of the locales are in the repository

Localize has the data of `en` only. Each other locale is a file of about
127 KB from the CDN of Localize, and a locale with no file gets the forms
of `en`, with no error.

- `config :localize, otp_app: :rescord` puts the files in
  `platform/priv/localize/locales`. The ten files (1.2 MB) are in Git, so
  a build needs no network for them, which the Nix package requires, and
  a release holds them.
- A download while Rescord runs stays off, which is the default.
- `Rescord.LocaleFilesTest` checks each file against the hashes that the
  package of Localize holds, and checks that each locale of the list has
  a file. After an update of Localize, run
  `mix localize.download_locales` and commit the files.
- The task also fetches data for inflection, which Rescord does not use.
  Git ignores it.

### What does not change

- An export (CSV, the file of a transfer) keeps ISO dates and plain
  numbers.
- The value of a form input is a plain number, and the browser draws the
  inputs of a date and a time.
- The Ash errors and the texts of Gettext stay as they are.

## Consequences

- With the default, a time of day is `8:30 am` where it was `08:30`, and
  a day has a comma: `Monday, 16 November 2026`. English (United Kingdom)
  has the 24 hour clock, and English (Ireland) has exactly the forms that
  Rescord had before.
- A new locale takes a line in `Rescord.Accounts.locales/0`, a name in
  `config :localize`, its file, and a row in `RescordWeb.LocaleTest`.
- A new release of CLDR, twice a year, comes with a new release of
  Localize and new files. A form can change with it, and a test that
  holds a form then fails.
- A form costs about 10 microseconds, where `Calendar.strftime` cost less
  than one. A page has tens of them.
- Localize starts seven processes, and its data adds about 5 MB to a
  release.
- Money, when Rescord has it, can use the same Localize: `ex_money` 6
  needs it.
