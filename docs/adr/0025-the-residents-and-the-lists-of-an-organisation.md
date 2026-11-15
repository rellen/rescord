# ADR 0025: The residents and the lists of an organisation

Status: accepted (the four choices are from the maintainer, 15 November 2026)

## Context

The maintainer chose the residents as the second part to build, and
answered four questions:

- A resident names a row of the list of its organisation, and that list
  holds each value that the organisation uses.
- The step builds all of section 5.2 of `docs/domain.md`.
- Rescord calculates the status. A member sets only `away for a time`.
- The size class and the coat are lists that an organisation can extend.
  The sex, the desex status, and the kinds of arrival and departure are
  fixed.

These are the first temporal resources with a table (ADR 0012).

## Decision

### The lists

- `Rescord.Lists` has seven dimensions: species, breed, colour, size class,
  coat, temperament and identifier kind. The other eight of section 7.2
  come with the parts that need them.
- Each dimension has a base list, outside the schemas, and a list in the
  schema of each organisation (ADR 0016). A row of the list of an
  organisation names a value of the base list, or it has a name of its own.
  A check constraint of the database holds that it is one of the two.
- A root user writes a base list. An administrator writes the list of the
  organisation. No action removes a value: a resident can name it.

### The residents

- `Rescord.Residents.Resident` holds the species, the sex, the date of
  birth, the size class and the coat. The name and the desex status are
  each a resource with one value (design rule 2). The breeds, the colours
  and the temperaments are ties. The identifiers, the arrival, the departure
  and the absence are resources about the resident.
- `register` and `revise` of the resident take the name, the desex status
  and the values of the ties as arguments. One change module writes them
  after the resident, in the same transaction and as of the same instant.
  No role has a grant to write them in another way.
- **The status is a calculation.** A resident with a departure has left, a
  resident with no arrival is expected, a resident with an absence at the
  instant of the read is away, and each other resident is in care. Rescord
  stores no status, so the status cannot disagree with the facts.
- **The period of an absence is the time away.** A member starts it and
  ends it. A read as of an instant in the period gives `away`.
- **The removal of a tie, a departure or an absence ends its period**, and
  does not archive the row. The same fact can then come again for the same
  resident, which an archived row with an open period would refuse. Such a
  removal has no version of its own. The removal of an identifier archives
  it, because an identifier has no rule of one at a time.
- A date of an arrival or a departure is not after today. Rescord does not
  know the time zone of an organisation, so today is the date in UTC and
  one day more.

### Two faults of ash_postgres 2.15.2

The generator writes the period foreign key of a temporal resource as a raw
statement. In a migration of the schemas of the organisations, the table of
the statement has no schema, and a table of the organisation that the key
refers to has the schema `public`. With either fault no organisation can be
created.

`Rescord.TenantMigrations.repair!/0` repairs the migrations, and
`Rescord.TenantMigrationsTest` fails while one has a fault. This is a
candidate to report to `ash_postgres`.

## Consequences

- A read with `as_of:` gives a resident and a list as they were at a past
  instant. The tests read the name, the species, the breeds, the status and
  the name of a list value in that way.
- Each write is as of the instant of the write. No page gives another
  instant.
- Rescord does not refuse a resident with no breed, colour, size class or
  coat, although section 5.2 gives a resident one of each or more. A member
  can know little about a resident that is expected.
- A resident cannot be removed yet, and a list value cannot be removed.
- A page that stays open after a write keeps what the person typed in its
  forms. The pages of a resident and of the lists thus open again after
  each write.
- `docs/domain.md`, section 8, has these as open points.
