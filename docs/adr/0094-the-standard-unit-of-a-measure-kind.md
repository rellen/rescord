# ADR 0094: The standard unit of a measure kind

Status: accepted (the maintainer said on 28 November 2026: "We should
avoid people changing units, or perhaps normalise them", and then
confirmed the nine decisions of issue 21, which is the design). It changes
one decision of ADR 0080, "A series has one unit: the unit of its newest
measurement." It builds on ADR 0030 and ADR 0039 (the journal and its
measurements), ADR 0071 (units of measure) and ADR 0073 (migrations), and
adds to ADR 0040 (the powers of a role) and ADR 0054 (the export).

## Context

A measurement of the journal has a number, a kind such as "Weight", and a
unit that the person chose, or no unit. A kind can name the units that a
measurement of it can have. Nothing said which of them the organisation
means when it reads a weight.

ADR 0080 then gave a series of measurements the unit of its newest
measurement. So one measurement in `kg`, among a year in `g`, changed the
chart, its scale, its table and each change to `kg`. Two residents of one
organisation could have their charts in two units. The journal, the cage
card and the record of a resident wrote each measurement as it was
recorded, so a person who read down the page had to convert in their
head.

Two answers were open: stop a person from recording another unit, or
convert what was recorded to one unit. A person who weighs on the scale
of a vet reads `kg` from it, and should record what the scale says. A
conversion in the head of a person is where a mistake is made.

## Decision

- **A measure kind names its standard unit, or none.** `standard_unit_id`
  of `Rescord.Lists.MeasureKind` names a unit of the list of the
  organisation. It is the unit in which Rescord shows each measurement of
  the kind. A kind with no standard unit works as before: each
  measurement is shown as it was recorded, and a series has the unit of
  its newest measurement.
- **A person may record another unit of the same sort, and the record
  keeps what was typed.** `value` and `unit_id` of a measurement stay what
  the person recorded. Nothing is stored in a converted form. Rescord
  converts when it reads, with `Rescord.Units.convert/3`, so a new
  standard unit of a kind shows each old measurement in the new unit, and
  a mistake in a factor is a fix of the code and of no row.
- **A new measurement of a kind with a standard unit has that unit, or a
  unit that Rescord converts to it.** The validation
  `Rescord.Journal.Validations.UnitOfKind` refuses a measurement with no
  unit, and one in a unit that does not convert, such as `bag` for the
  standard unit `g`. When the kind names units too, the unit is one of
  them. `Rescord.Lists.units_for/2` and `accepted_units/2` hold the rule,
  for the journal and for the forms. A standard unit that the catalogue
  of `Rescord.Units` does not know, such as `bag`, accepts itself alone.
- **A measurement from before stays.** Rescord checks the rule when a
  person writes a measurement, and when a correction gives a kind or a
  unit. A correction of the value or of the words of an old measurement
  with no unit works. Such a measurement is shown as it was recorded, and
  is not a point of a chart: the card says how many are not in the chart,
  and the table has them (ADR 0080).
- **Each read shows the standard unit.** `Rescord.Journal.Standard.of/1`
  gives a measurement in the standard unit of its kind, beside what was
  recorded, and rounds nothing. `Rescord.Journal.Series` has the standard
  unit of its kind as the unit of the series. So the charts, the tables,
  the cards of a group, the journal, the timeline, the cage card and the
  record of a resident are in the standard unit. A page that shows a
  converted value rounds it to four significant digits, never to less
  than the whole number, and says what was recorded beside it:
  "610 g (recorded as 0.61 kg)".
- **The forms choose the standard unit.** When a person chooses what was
  measured, the unit of the form is the standard unit of that kind. The
  form offers that unit and the units that convert to it, has no choice
  "No unit", and the field is required.
- **The export has both.** `measurements.csv` keeps `value` and `unit_id`
  as they were recorded, and has two new columns at its end:
  `standard_value`, with no rounding, and `standard_unit`, the name of
  the standard unit. Both are empty for a measurement of a kind with no
  standard unit, and for one that Rescord does not convert.
- **The person who sets the units of a kind sets its standard unit**: the
  action `set_standard_unit`, with the grant of `set_units` (the power
  that changes the lists, ADR 0040), on the page Lists. The standard unit
  is a unit of the organisation, and one of the units of the kind when
  the kind names units. `set_units` refuses a list that leaves the
  standard unit out. A kind that gets exactly one unit gets it as its
  standard unit.
- **The migration fills the standard unit only where the answer is no
  guess.** In each organisation: (1) a kind that names exactly one unit
  gets that unit; (2) otherwise, a kind whose measurements all have one
  and the same unit, and none without a unit, gets that unit, when the
  kind names no unit or names that one. Each other kind keeps no standard
  unit, and an administrator chooses one. The migration changes no
  measurement.
- **The base list of the measure kinds has no standard unit.** A unit is
  a value of the list of an organisation, and two organisations can weigh
  in two units.
- **The column has no foreign key.** A measure kind is temporal, and a
  version of a kind can be older than the unit: the same reason as for
  `unit_ids`. The validation checks that the unit is there.

## Not in this work

A transfer of a resident carries each measurement as it was recorded
(ADR 0042): the refuge that receives it has its own kinds and its own
standard units. The dose calculator (ADR 0072) reads a weight as a
quantity and converts it for its sum already, so it does not change. A
standard unit for each species, such as `g` for a guinea pig and `kg` for
a dog, under one kind "Weight". A conversion of the rows that are there
to the standard unit. A standard unit for the items of the inventory.

## Consequences

- One migration, with its line in the upgrade notes (ADR 0073):
  `add_the_standard_unit_of_a_measure_kind`, in each organisation. It
  adds a column and fills it by the two rules. After an upgrade, a kind
  that the migration gave a standard unit refuses a new measurement with
  no unit, or in a unit that does not convert. An administrator changes
  or removes the standard unit on the page Lists.
- A measurement in a unit that only the organisation knows, such as
  `bag`, cannot be a new measurement of a kind with a standard unit that
  Rescord converts. The page Lists says so beside the kind.
- A tool that reads `measurements.csv` by the position of a column does
  not change: the two new columns are the last.
- A read converts each measurement in another unit each time. The
  conversion is arithmetic on a `Decimal` with no query, and the standard
  unit comes with the load of the kind.
- When an administrator changes the standard unit of a kind, each page
  changes at once and no measurement does. The history of the kind keeps
  each standard unit that it had, and from when.
- A person who reads the journal sees "610 g (recorded as 0.61 kg)", so
  the page never hides what was typed.
