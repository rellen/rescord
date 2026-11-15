# ADR 0024: A domain holds its own grants

Status: accepted

## Context

ADR 0021 put the grants of each role in `Rescord.Accounts.Grants`, in code.
`docs/architecture.md` left open how a second domain adds its grants. The
lists and the residents are the second and the third domain.

The grants name resources. If `Rescord.Accounts.Grants` named a resident, the
accounts would use the residents. The residents use the accounts already,
for the check `Rescord.Accounts.Checks.Granted`. The compiler refuses two
boundaries that use each other (ADR 0009).

## Decision

- Each domain other than the accounts holds its grants in a module of its
  own: `Rescord.Lists.Grants` and `Rescord.Residents.Grants`. The module has
  the behaviour `Rescord.Accounts.Grants`: `grants/0`, and `filter/2` for a
  scope of its own.
- The configuration names the modules, in `config :rescord, :grant_sources`.
  `Rescord.Accounts.Grants` reads the list when it compiles, and asks each
  source at run time. It thus names no resource of another domain.
- The boundary of the accounts exports `Rescord.Accounts.Grants` and
  `Rescord.Accounts.Checks.Granted`.
- A domain gives the web layer a function that says whether a role can run
  an action at all, for example `Rescord.Residents.role_can?/3`. It calls
  `Rescord.Accounts.granted?/3`.

## Consequences

- A new domain adds its module to the configuration. A domain that is not
  in the list has no grants: each member is refused, and a test that reads
  finds an empty result.
- The test of the grants reads each source, so a grant that names an action
  that is not there fails the test.
- A grant is still in code. ADR 0021 says when that changes.
