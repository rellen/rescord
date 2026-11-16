# ADR 0030: The journal of a resident

Status: accepted (the answers are from the maintainer, 16 November 2026)

## Context

Section 5.6 of `docs/domain.md` gives each resident a journal, which holds
its medical history. The maintainer answered two questions about it: the
author of an entry and an administrator correct it, and a member can give
the time that a thing happened.

## Decision

- `Rescord.Journal` is a domain of its own. The tasks will use it: a
  completed `medicate` task writes an entry for the dose.
- **A journal entry** has a kind from a fixed list of eleven, the words of
  the member, the time that the thing happened, and its author.
- **The time that the thing happened is an attribute**, `happened_at`, and
  not the instant of the write. The journal is in the order of that time.
  It is the time of the write when the member gives none, and it is never
  after that. An entry that a member writes late is thus in its place in
  the journal, and the history still says when the member wrote it.
- **The facts of a medical kind are resources of their own**: the condition
  of a diagnosis, the value of a measurement, the kind of a procedure, the
  vaccine of a vaccination, a prescription, and a dose. `write` and
  `correct` of the entry take them as arguments, and one change writes them
  in the same transaction. A new entry is refused without the facts that
  its kind needs. An entry of each other kind needs words.
- **The weight of a resident is a measurement.** The page of a resident
  shows the newest measurement of each kind.
- **The author is the id of the user**, in a plain attribute that no action
  takes as input. A user is not temporal, so the database holds no key from
  the entry to the user.
- **A correction** is for the author, an administrator and a root user. A
  member has the grant with the scope `own`, which is the filter
  `author_id == ^actor(:id)`. A correction is a new version, so the history
  keeps the entry as it was.
- **An addendum** is a new entry that names, in `follows`, the entry that it
  adds to. It has the kind of that entry, and needs words only.
- Four more lists that an organisation can extend come with the journal:
  the condition, the measure kind, the procedure kind and the unit.
- A person with no sign-in gets `forbidden` from the policy. The change
  that sets the author does nothing for such a person: an error from it
  gave that person another answer.

## Consequences

- A measurement names its kind and its unit, and nothing ties a kind to one
  unit. A member can record a weight in another unit by mistake.
- An entry has no attachment yet. A file needs a place to keep it.
- The timeline of section 5.6, which shows the entries together with the
  changes that Rescord records, is not built. The journal page shows the
  entries only.
- A member who is removed from the organisation is `a person who is not a
  member now` on the entries that they wrote: a member cannot read the
  address of a user who is not a member.
