# ADR 0105: Former members, and the erasure of a member on request

Status: accepted. Issue 31 is the design, and the maintainer answered
each of its 17 judgement calls on 28 November 2026 (a comment on the
issue). This ADR records what is built. Part 1, the removal of a
member, is built. Part 2, the erasure on request, is built with its
pages and its notices.

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

## Decision, part 2: an erasure on request

A new domain, `Rescord.Privacy`, holds the requests
(`Rescord.Privacy.Request`), the settings of privacy of an organisation
(`Rescord.Privacy.Settings`), and the functions `erase/3`,
`erase_account/3`, `daily/1` and `reapply_erasures/0`.

- **A request first.** Each erasure in an organisation starts from a
  request: the member asked from their own page (`ask`), or a person with
  the new power `privacy` recorded one that came by email, by letter or
  in person (`record`). It is due one calendar month after it arrived, or
  after the identity was confirmed; an extension is at most two more
  months, with a reason and the day the person was told inside the first
  month (GDPR Article 12(3)). An erasure of the account, and the
  pseudonymisation after the months of the settings, write a closed line
  of their own (`closed`), because nobody in the organisation asked.
- **One transaction.** `erase/3` runs in `Ash.transact/3` under one
  correlation id (ADR 0101), which the request keeps. Ash sends the
  notifications of the nested actions after the commit. It removes a
  member first (`remove`, so the listeners of part 1 run), then runs the
  new action `erase` of the member: `erased_at`, and `former_number`, one
  more than the largest of the organisation, under a unique index.
- **The listeners of `:member_erased`.** The conversations of the person
  with Ruby go with their messages. Each calendar feed of the person,
  also a revoked one, becomes "Feed of former member N", and its old name
  is redacted in its versions. The comments of the person go, unless the
  person who erased chose to keep them (the read `of_erased_author` holds
  the choice); their follows and notifications go.
- **The hold of the money records.** When an expense younger than
  `money_years` (7 at first) names the person as payer, author, decider
  or the person who paid back, the member row keeps `held_email`,
  encrypted with AshCloak, and `held_until`. The pages and the reports of
  the expenses call `Accounts.labels(options, held: true)` and show the
  email with "held for the money records until" the day. The daily job
  lets it go after that day.
- **The account.** When the person is then a member of no organisation
  and is no root user, the account goes in the same transaction: each
  former membership elsewhere is pseudonymised with a closed line, the
  user keeps its row with no email and with `erased_at` (a check of the
  database holds the two together), each token goes, the email is
  redacted in the versions of the user, the devices and the topic of
  ntfy go, and each waiting job whose arguments hold the email is
  deleted. A root user is never erased.
- **The redaction of versions.** `Rescord.Redaction.redact_versions/4`
  replaces fields of `changes` with "REDACTED" for named rows. It is the
  one change of the paper trail, and `Rescord.RedactionTest` fails for a
  caller other than the erasure.
- **The email of the outcome** goes in a job of the transaction, unless
  the request came by letter. The address stays in the job until the
  pruner of Oban deletes it, one day later.
- **A marker in the store.** After the commit, each erased member gets
  `<organisation id>/erasures/<member id>` in the store, with ids, the
  number and the day, and no email. `file_keys/1` names it, so
  `bin/check-files` counts it as named. `bin/restore` runs
  `bin/reapply-erasures`, which erases again each person whose marker
  the restored database does not show, with the number of the marker, and
  writes each marker that is missing.
- **Who erases.** The power `privacy` (the role Administrator at first).
  A person with it does not erase a member whose role has `privacy` or
  `members`: only a root user does, so two administrators cannot erase
  each other.
- **The daily job** (`Rescord.Privacy.Workers.Daily`, 03:53 UTC) lets go
  of each hold that ended, deletes each closed request older than
  `closed_request_years` (3 at first), and, when
  `pseudonymise_after_months` is set, pseudonymises each former member
  who left longer ago, keeping their comments.

The pages and the notices:

- **The page Privacy** of an organisation (`/o/<short name>/privacy`,
  `RescordWeb.PrivacyLive`, a link in the header of the members page).
  Each member reads what the organisation keeps, asks for the erasure of
  their data, and sees their own requests. A person with the power
  `privacy` also sees the requests that wait, the soonest due first,
  records a request that came another way, sees the closed ones, and
  keeps the settings. The members page links each member that the person
  may erase to the form, with `?member=<id>`.
- **The page of a request** (`RescordWeb.PrivacyRequestLive`) says what
  goes, what stays with no name, what Rescord cannot reach, and when the
  money records let go, before the button. The person chooses for the
  comments, ticks a box, and erases. It also extends, refuses with a
  reason, records a withdrawal, and records the day of the answer to a
  request by letter. A request that waits is a row of the first page
  (ADR 0065), in alert in its last 7 days.
- **The privacy settings of the server** are one row of a shared
  resource, `Rescord.Privacy.InstanceSettings`, which a root user keeps at
  `/root/privacy`: who runs the server, where a person writes to the
  operator, where the servers are, the mail provider and the days of the
  backups. It holds no secret, and each person may read it, because the
  notices are public. Nothing in it is needed before the first sign-in,
  so it is no environment variable (ADR 0068).
- **The notices** are pages with no sign-in. `/privacy` is the notice of
  the server, for the account. `/privacy/<notice id>` is the notice of an
  organisation, from a template that its settings and the settings of
  the server fill. `notice_id` is a random id of the organisation, made
  only for the link, so the link names no organisation and is not its id.
  The action `new_notice_id`, with the power `privacy`, makes a new one,
  and the old link ends. A notice with a blank that nobody filled says
  that it is not finished, and shows nothing else.

Where it differs from issue 31:

- `ruby_usage` keeps the user id. Each other table keeps the id too, and
  the account of an erased person names nobody, so a nil there adds
  nothing, and the identity of a row of usage holds the id.
- A person erased in an organisation is not invited there again with the
  same account: the records would name them again. The invitation says
  so. Once the account is erased, the same address makes a new user.
- The marker of an account is the marker of each of its members: an
  account erasure erases each member row.
- There is no resource for a request to the operator. A root user
  erases an account at `/root/privacy` and types how the request came and
  how they checked who asked. Each organisation of the person gets a
  closed line of the kind `account` that keeps both, so the proof is with
  each organisation that held the data.
- The invitation email does not link to the notice of the organisation
  yet.

## Consequences

- A root user is no longer "a person who is not a member now" to the
  members of an organisation: their work says "Rescord operator".
- The comments work (issue 29) signs a removed member in the same way.
  It switches to `people/1` in one place when both are on `main`.
- An id that names no member and no root user, such as a root user whose
  root was revoked, still reads "a person who is not a member now".
