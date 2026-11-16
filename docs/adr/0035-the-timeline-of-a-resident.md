# ADR 0035: The timeline of a resident

Status: accepted

## Context

Section 5.6 of `docs/domain.md` defines the timeline of a resident: its
journal entries together with the changes that Rescord records, in order of
time. Rescord records a change in the resource that holds the fact: a move
is a new version of a placement. The journal does not record it again
(ADR 0030).

Each temporal resource keeps each version of a record as a row with a
period, with the action and the user who made it (ADR 0012).

## Decision

- **`Rescord.History` reads versions as changes**, with no database. The
  first version of a record is where it started. Each later version is a
  change. A last version whose period has an end is where it ended.
- **Each domain gives the changes of its own resources.**
  `Rescord.Residents.changes/2` gives the changes of the name, the arrival,
  the departure, each absence and each group of a resident.
  `Rescord.Locations.changes/2` gives the changes of its own placements.
  No domain reads the versions of another domain.
- **`Rescord.Journal.timeline/2` puts them in one list** with the journal
  entries, the newest first. A journal entry is at the time that the thing
  happened. A change is at the time of its version: the time that the
  member gave for it, or the time of the write.
- **The resident decides who reads its timeline.** The versions have no
  policy of their own. A person who cannot read the resident gets an empty
  list.
- **The page reads only**, at
  `/o/<short name>/residents/<id>/timeline`. It says each event in words,
  with its time in the organisation and the person who made it.

## Consequences

- An end has no person. The versions do not record who ended a record:
  who marked a resident as back, or who took it out of a group.
- The timeline has the placements of the resident itself. It does not have
  the placements of its groups, so a move of a whole group is not there.
- The timeline does not have the breeds, the colours, the temperaments, the
  identifiers, the desex status or the parents of a resident. Each can come
  in the same way.
- An arrival and a departure are at the time that a member recorded them,
  and not on the date of the arrival or the departure. The words give that
  date.
- A location or a group that is closed has no name on the timeline: the page
  says that it is not here now.
- The page reads each version of each fact of the resident. A resident with
  many years of history needs pages of events.
