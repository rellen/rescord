# ADR 0021: The roles and the grants start in code

Status: accepted

## Context

`docs/architecture.md` decided that authorization is our own system in the
manner of `ash_grant`: a role appears in no policy, a grant names a
resource, an action and a scope, and a scope is a named filter. It left open
how a grant is written and where the roles are stored.

The maintainer decided the roles of the start: administrator and member, with
a root user outside the system, who can do anything
(`docs/domain.md`, section 5.1). The first resource that needs them is the
member of an organisation.

## Decision

- A member has a role: administrator or member. No action takes the role as
  input.
- `Rescord.Accounts.Grants` holds the grants of each role, as
  `{resource, action, scope}`. It also holds the filter of each scope.
- **The policy of a resource of an organisation is one check**,
  `Rescord.Accounts.Checks.Granted`. The check reads the member of the actor
  in the tenant of the request, finds the grant of that role for the action,
  and gives the filter of its scope. A read returns the records of the scope,
  and a write is refused outside it.
- **A root user is outside the grants.** Each such resource has a bypass for
  an actor whose `root?` is true, before the check.
- A page asks `Rescord.Accounts.role_can?/3` whether to show a form or a
  button. The policy decides again when the action runs.

## Consequences

- A new action that a role can run takes one line in the grants. A resource
  without a grant for a role refuses that role.
- The check reads one member for each request that it decides. That is one
  small query, in the schema of the organisation.
- The roles are the same for each organisation. When an organisation needs
  roles of its own, the roles and the grants move to resources in its schema:
  the estimate of `docs/domain.md` has `Role`, `MemberRole` and `Grant` for
  that. The check then reads them in place of the module.
- The grants name resources of one domain today. A second domain needs a way
  to add its grants: not decided.
- `Rescord.Accounts.OrganisationTest` holds the grants to the resources: each
  grant names an action that exists. Seven changes to the rules each turned a
  test red: a scope that is ignored, a missing grant that passes, a root user
  inside the grants, an organisation that opens for anybody, a member who
  can invite, a root page for any user, and an organisation from anybody.
