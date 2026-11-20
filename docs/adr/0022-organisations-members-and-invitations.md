# ADR 0022: Organisations, members and invitations

Status: accepted

## Context

The maintainer decided the rules (`docs/domain.md`, section 5.1): a root user
creates an organisation and invites its administrators, an administrator
invites members, a page names its organisation in the path, and each
organisation has a schema of its own (ADR 0011). This record holds the
decisions that the work made on the way.

## Decision

- **A user says that it is a root user**, in the attribute `root?`. No action
  takes it as input. `Rescord.Accounts.bootstrap_root/1` makes the first
  root user from IEx, and does nothing when there is one.
- **An organisation is outside the schemas**, with the users. Its schema has
  the name `org_` and its id, so a new short name needs no new schema.
  AshPostgres makes the schema, and runs the tenant migrations in it, when
  the organisation is created.
- **A member is inside the schema**, and names a user, who is outside it.
- **An invitation is not a record, and has no token.** It makes the user when
  the address has none, makes the member, and sends an email that says where
  to sign in. The person then asks for a sign-in link, as each user does.
- **A user reads only their own record.** The address of another member comes
  from one calculation of the member, which reads the users with no policy.
- Only a root user reads an organisation through its actions. Another user
  reaches an organisation through `Rescord.Accounts.organisations_for/1` and
  `organisation_for/2`, which look for their member.
- The pages below `/o/:organisation` are in one live session. Its hook finds
  the organisation and the member, and assigns the role. A page that the
  person cannot open, and a page that is not there, give the same answer.
- `ash_authentication_phoenix` is not a dependency. The core package has the
  functions for the session of a plug and of a LiveView, and the pages are
  ours (ADR 0018).
- `simple_sat` is the SAT solver that Ash needs for policies. It is plain
  Elixir, so it needs no compiler for C.
- The user, the organisation and the member are not temporal. Each has an
  identity that is unique at each time, and nobody has tested an identity,
  or AshAuthentication, on a temporal resource. Their history is in their
  paper trails, which name the user who made each change.

## Consequences

- The list of the organisations of a user is one query for each
  organisation, because a member is in the schema of its organisation. That
  is sufficient for tens of organisations.
- A new organisation takes a lock on the table of the users, while its schema
  gets a table that names the users. Two such transactions at one time can
  stop each other. A test that creates an organisation therefore does not
  run beside other tests.
- An email of an invitation that fails does not undo the invitation. The
  fault goes to the log, and the person can still ask for a sign-in link.
- A removed member is archived, and the user can be invited again.
- The limit of a client counts the address of the connection. Behind a proxy
  that is the address of the proxy: the deployment has to pass the real one.
  Not decided. (Decided later: ADR 0046 takes the address of the client
  from a trusted proxy.)
- A release still sends no email (`docs/architecture.md`, "Sign-in and
  organisations"). Until the mailer is set up, the sign-in works in
  development only, where each email is at `/dev/mailbox`. (Changed later:
  ADR 0044 sends the mail through the SMTP server of the operator.)
