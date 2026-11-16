# ADR 0027: A temporal resource names an attribute after its column

Status: accepted

## Context

A boolean attribute often has a name that ends in `?`, and a column of
another name, for example the attribute `root?` with `source :is_root`.

On a temporal resource the paper trail is on the rows of the resource, and
the version resource reads the same table (ADR 0012). AshPaperTrail 0.8.1
copies each attribute to the version resource without its `source`. The
version resource thus asks for a column with the name of the attribute. A
read of the versions of a list failed with `undefined_column` for the
attribute `retired?`. The resident had the same fault, for the estimate of a
date of birth, and no test read its versions.

## Decision

- On a temporal resource with a paper trail, an attribute has the name of
  its column. Write `:retired`, and not `:retired?` with a `source`.
- `Rescord.Resource.Checks.NoSourceOnTemporal` refuses to compile such a
  resource with a `source` that differs from the name of the attribute.
- A resource that is not temporal can use `source`: its versions are in a
  table of their own.
- `Rescord.VersionsTest` reads the version resource of each resource of the
  lists and the residents.
- The column `born_on_is_estimated` of a resident gets the name
  `born_on_estimated`. The generator wrote a new column and the removal of
  the old one. We changed that to a rename, which keeps each value.

## Consequences

- A boolean attribute of a temporal resource has no `?` in its name.
- This is a candidate to report to `ash_paper_trail`. When it copies the
  `source`, the check can go.
- Read each migration that the generator makes for a change of a name. Its
  answer to a new name with no person at the keyboard is a new column and a
  removal.
