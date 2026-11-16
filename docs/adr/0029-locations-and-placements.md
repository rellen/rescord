# ADR 0029: Locations and placements

Status: accepted (the answers are from the maintainer, 16 November 2026)

## Context

Section 5.5 of `docs/domain.md` gives an organisation its housing. The
maintainer answered four questions about it:

- A resident with a placement of its own lives there while it lasts, and in
  each other case it lives with its group.
- A location can have a capacity. A placement over it is permitted, and the
  page says so.
- A member can say when a thing happened, and that time is never after now.
- The model must not fit the housing of one organisation only.

## Decision

- `Rescord.Locations` is a domain of its own, because the inventory and the
  tasks use a location too. It uses the residents, and the residents do not
  use it.
- **A location** has a name, a kind from a list that the organisation can
  extend, and a capacity that is not necessary. A location that is used no
  more is closed, which archives it.
- **`LocationParent` is the tie** that says which location contains a
  location. A location is inside one other location, or inside none, and
  never inside itself: a validation walks from the new parent to the top.
- **A placement** names a location and a resident or a group. A check
  constraint of the database holds that it is one of the two. Its period is
  the time in the location, and a move is a new version, so a read as of a
  past instant gives where each one was.
- **Where a resident lives.** `Rescord.Locations.home/2` gives the placement
  of the resident, or the placements of its groups when it has none.
  `tree/1` counts a resident in one location only: a member of a group with
  a placement of its own is not in the count of the location of the group.
- **The count of a location** is the residents that live there or in a
  location inside it. A location is over its capacity when the count is
  more than the capacity. Nothing refuses a placement for that.
- **A time that a member gives.** The form of a placement takes a local date
  and time. `Rescord.Accounts.instant/2` turns it into an instant, in the
  time zone of the organisation, and refuses a time after now. The write
  then happens as of that instant (`as_of:`).
- An administrator shapes the housing. Each member places and moves a
  resident or a group.
- **The page draws the housing as cards in cards.** A location with
  locations inside it takes a whole row, and the ones with nothing inside
  share a row. The markup is the same for each depth and each shape.
- The kind of a location is the ninth list that an organisation can extend.

## Consequences

- A write as of a past instant needs each record that it names to be there
  at that instant. A move to a time before the resident was recorded is
  refused, with words that name the field and not the reason.
- Only a placement has a time that a member gives. An absence, a change to a
  group and a journal entry do not have it yet.
- `tree/1` reads each location, tie, placement and group of the
  organisation for one page. That is sufficient for hundreds of locations.
- The capacity of a location that contains others is not the sum of theirs:
  an organisation gives each one its own, or none.
