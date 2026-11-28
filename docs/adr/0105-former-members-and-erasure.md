# ADR 0105: Former members, and the erasure of a member on request

Status: accepted. Issue 31 is the design, and the maintainer answered
each of its 17 judgement calls on 28 November 2026 (a comment on the
issue). This ADR records what is built. Part 1, the removal of a
member, is built. Part 2, the erasure on request, follows.

The legal points of issue 31 are general information for the design of
software, and not legal advice.

## Context

`Member.remove` archived the member row (AshArchival), and nothing else
happened. Each page named a person by the email of a current member, so
the records of a member who left said "a person who is not a member
now", or "A person who left" on the expenses. The owed table of the
expense report grouped by those words, so each removed payer fell into
one row: a fault in the accounts. A task that was due for the removed
person alone was on nobody's list, a routine kept the person, the
calendar feeds of the person stayed with their token hashes, an
invitation that waited was still sent, and a root user could remove the
last administrator.

The maintainer chose two levels for members and administrators. A
member who is removed from an organisation is deactivated there, and
their history stays attributed to them with a mark, as in Linear. A
member who asks for erasure is pseudonymised as "Former member N", their
contact details and account are wiped, and only what the law needs
stays.

## Decision, part 1: a removed member

- **One name for each person.** `Rescord.Accounts.people/1` gives, for
  each user id that the records of an organisation can name, a label and
  a state: `:member` (the email), `:former` ("email (former member)"),
  `:operator` (a root user who is not a member, "Rescord operator", and
  the email to that root user). `labels/1` gives the labels alone. They
  read the new action `:with_former` of `Member`, which AshArchival does
  not filter, so they include the archived rows. A person who is a member
  again is a member. The journal, the timeline, the expenses, the stock
  movements of an item, the tasks of a day, the expense report and its
  CSV and the task sheet use it.
- **The owed table groups by the payer**, and the label comes after. Two
  people who left are two rows.
- **A removal emits `:member_removed`** of `Rescord.Accounts.Signals`
  (ADR 0067), with the user id. The listeners run in its transaction:
  - each task that is due and is for the person lets go of them
    (`Task.forget_member`), and a task left with nobody is for anybody,
    as a task with no member always was. A task that is done or skipped
    keeps the person;
  - each routine lets go of them (`Routine.forget_member`), so the tasks
    that it makes later do not name them;
  - each calendar feed of the person is revoked (`Feed.revoke`), so that
    nothing waits for a read of the member to fail.
- **The last member who can change the members stays.**
  `Rescord.Accounts.Validations.NotTheLastManager` refuses to remove the
  last member whose role has the power `members`, as `NotTheLastRoot`
  does for root.
- **An invitation that waits is not sent** when its member was removed
  before the job ran.
- **The members page** asks before a removal, says what it does, and
  lists the former members with the day each one left and a button
  "Invite again". The export puts the former members in `members.csv`,
  with the column `former?`, so that each id of another file names a row.

Invited again, a person gets their history back, because the records
name the user. A calendar feed does not come back: it named the member.

## Consequences

- A root user is no longer "a person who is not a member now" to the
  members of an organisation: their work says "Rescord operator".
- The comments work (issue 29) signs a removed member in the same way.
  It switches to `people/1` in one place when both are on `main`.
- An id that names no member and no root user, such as a root user whose
  root was revoked, still reads "a person who is not a member now".
