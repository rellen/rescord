# ADR 0085: The markings of a resident, as free text

Status: accepted (the maintainer chose the field on 28 November 2026). It
adds one attribute to the resident of ADR 0025. The design is in issue 17.

## Context

Many residents carry no microchip and no ear tag: guinea pigs, for
example. A person then tells two residents apart by the name, the photos,
the colour and the coat. The colour and the coat are values of lists of
the organisation, and a list cannot hold what is particular to one animal:
a torn ear, a white blaze on the nose, a rosette on the right hip.

A person could write such a mark in a note of the journal or in the
caption of a photo. Neither is on the cage card, and neither is where a
person looks for the facts of a resident.

## Decision

- **A resident has `markings`: text, at most 300 characters, that it can
  be without.** Ash trims it, and text with no character is no value. No
  form and no action needs it. 300 characters fit on the cage card, which
  stays one page.
- **It is an attribute of `Rescord.Residents.Resident`**, like the sex and
  the date of birth, and not a table of its own. Design rule 2 gives a
  fact a table when a page shows its history, as for the name and the
  desex status. The markings change seldom, and the paper trail of the
  resident keeps each change with who made it.
- **It is free text and not a list of the organisation.** A mark belongs
  to one animal, so a list would have one value for each resident.
- **`register` and `revise` accept it.** There is no new action and no new
  power: who can change the facts of a resident can change its markings.
  The form sends the markings with each change, so a form with none takes
  them away. A change that does not name them keeps them.
- **A place shows the markings only when the resident has them.** No page
  and no report has a dash or the words "Not recorded" for them, as for
  the identifiers:
  - the form of a resident has the field "Markings" after the coat;
  - the page of a resident has the row in "About", after the coat;
  - the cage card has the row after the colour, and the record of a
    resident after the coat (ADR 0076). The register has no column for
    them: the page has no width for free text;
  - the copy of a transfer holds them under `"markings"` in its facts
    (ADR 0042), and the page of a transfer shows them. A copy from a
    server with an older version has no such key, and that is no
    markings;
  - `residents.csv` of the export has the column `markings`, with no
    code: the export writes each public attribute (ADR 0054).
- **The search of the residents page finds a resident by its name or by
  its markings**, in any case of the letters. The markings have no column
  in the table, so Cinder cannot search them by itself:
  `Rescord.Residents.with_text/2` narrows the query, and the page gives it
  to Cinder as the search function. It is a function of the domain,
  because the web layer does not write a filter of Ash.

## Consequences

- One migration in each organisation,
  `20261128065227_add_the_markings_of_a_resident`: it adds a column that
  can be empty to the table of the residents, and changes no row. The
  upgrade notes name it (ADR 0073).
- The markings have no structure: no list of marks, no place on the body,
  no drawing. A search finds a word of them, and nothing counts them.
- The page of a resident does not show the markings that a resident had
  before. The paper trail holds them.
- The assistant (ADR 0069) has no tool that reads the markings yet.
