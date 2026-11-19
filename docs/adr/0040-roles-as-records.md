# ADR 0040: Roles as records

Status: accepted (the answers are from the maintainer, 18 November 2026).
It supersedes the part of ADR 0021 that keeps the roles in code.

## Context

ADR 0021 kept two roles, administrator and member, in code, and said that
the roles move to the database when an organisation needs roles of its
own. The maintainer answered: the administrators of an organisation define
its roles, and tick what each role may do. Each organisation starts with an
administrator and a member, as before.

## Decision

- **A role is a record of the organisation**, `Rescord.Accounts.Role`, in
  its schema, with a name and a list of powers. A member names one role.
- **A power is one area of work**, such as `:journal`, `:routines` or
  `:stock`. Each domain says which grants each of its powers gives, in its
  source of grants (ADR 0024): `reads/0` and `powers/0`. A grant is still
  `{resource, action, scope}`, and the policy of each resource is still
  the one check `Rescord.Accounts.Checks.Granted`. A page ticks powers, and
  never a single action.
- **Each role reads.** The reads of each domain are in each role, so a role
  with no power is a role that reads and changes nothing.
- **The two roles of the start** come from the tenant migration that makes
  the table, in each schema: `Administrator`, with the key
  `:administrator` and each power, and `Member`, with the key `:member`
  and the powers of a member of ADR 0021. The migration gives each member
  the role of its old column. A test holds the grants of the two records
  to those of the two roles of ADR 0021. A later power that the
  administrators have goes into their role in the migration of its step.
- **A person gives only the powers that their own role has**: to a role
  that they define or change, and to a member, through a role. So nobody
  gives themselves, or another person, a power that they do not have. A
  root user is outside this rule, as it is outside the grants.
- **The role with the key `:administrator` keeps the power `:roles`**, so
  the organisation always has a person who can change the roles. The two
  roles with a key do not go, and nor does a role that a member has.
- **A person with the power `:members` changes and removes a member whose
  role does not have that power.** That is the rule of ADR 0021, that an
  administrator does not remove another administrator, for each role.
- **A change to a role closes each open page of each member with that
  role** (ADR 0036), so each page opens again with the new powers.
- The words of each power and the areas of the page are in
  `RescordWeb.RoleWords`. The page reads a power from a form with
  `RoleWords.power_of/1`, which makes no atom.

## Consequences

- The check reads the member and its role for each request that it
  decides: two small queries in the schema of the organisation.
- The scope `:members` reads the roles of the organisation, because the
  powers of a role are in the database.
- A new action of a domain takes one line in a power. A new power takes a
  key in `Rescord.Accounts.Grants.power_keys/0`, words in
  `RescordWeb.RoleWords`, and a line in the migration that gives it to the
  administrators.
