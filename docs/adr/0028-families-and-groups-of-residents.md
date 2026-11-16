# ADR 0028: Families and groups of residents

Status: accepted (the answers are from the maintainer, 16 November 2026)

## Context

Sections 5.3 and 5.4 of `docs/domain.md` give a resident its relatives and
its groups. The maintainer answered two questions: a parent is a resident of
the organisation, and a resident can be in more than one group at one time.

## Decision

- **A parent link** says that one resident is the mother or the father of
  another. A resident has one of each at most. A resident is not its own
  parent, and not a parent of one of its own parents: a validation walks
  from the parent to the top and refuses a circle.
- **A family** is a named set of residents. A resident is in a family one
  time.
- **A group** has a kind from the list of the organisation, a name that is
  not necessary, and its members. The period of a member is the time in the
  group, so a read as of a past instant gives the members at that instant.
  A group that is no more is closed, which archives it.
- **Rescord stores no other relation.** `Rescord.Residents.Kinship` is plain
  Elixir that gives a group its words from the parent links and the
  families of its members:
  - two residents are siblings when they have a parent in common, or when
    they are in one family and neither has a parent link;
  - a group with a parent and its young reads `Mother, father and two
    daughters`;
  - a group of siblings reads `Sisters`, `Three brothers` or `Brother and
    sister`;
  - each other member is `unrelated`, with its sex;
  - a group with no relation has no words.
- A member can replace the words with their own. The group stores those
  words, and stores nothing when the words of Rescord apply.
- A group with no name has the names of its members for a name.
- The kind of a group is the eighth list that an organisation can extend.

## Consequences

- The words use `male` and `female`, and not the words of a species, such as
  `boar` and `sow`. Rescord has no such words for a species.
- A relative that the links do not give in one step, for example a
  grandmother or an aunt, has no word yet.
- The words of a group are calculated at each read. For a list of many
  groups, that is two queries for each group.
- A resident that is removed stays in the parent links and the groups of
  other residents as a link that reads nothing.
