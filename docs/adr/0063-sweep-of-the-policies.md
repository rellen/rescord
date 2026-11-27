# ADR 0063: A test tries each action as the actors who must be refused

Status: accepted (the maintainer chose it on 28 November 2026, as the first
of the concepts of the review of Chironium: "a test that tries every action
as an actor who must be refused"). It changes one point of ADR 0035: a
version resource now has a policy.

## Context

The grants say what a role can do (ADR 0021, ADR 0024, ADR 0040), and the
tests of each domain show that a member without a power is refused for the
actions of that domain. No test asked the other question for the whole
system: is there an action that somebody can run, and that no grant gives?
Such an action comes from a resource with no authorizer, from a policy that
any actor passes, or from a new action that nobody gave a thought to. A
test of one domain does not find it, because nobody wrote a test for what
nobody thought of.

The concept is from the review of Chironium, which has such a test for its
patients. Nothing was copied: Chironium is under the AGPL, and this test is
written new for the grants of Rescord.

## Decision

- **`Rescord.PolicySweepTest` asks the policies about each action of each
  resource of each domain**, the version resources included. It reads the
  domains from the configuration and the actions from Ash, so a new
  resource or action is in the sweep with no change to the test.
- **Five actors, in one refuge**: nobody; a stranger, who is an
  administrator of a refuge with no tie to this one; a reader, whose role
  has no power; a member, with the role `:member`; and an administrator.
- **The rule: an action that an actor can run is a grant of the role of
  that actor.** Nobody and the stranger have no grant. Each other action
  must be in `open_on_purpose/0` of the test, a list of the actions that
  are open on purpose, each with the reason and the test that holds what
  the action still keeps from the actor. The list starts with three kinds:
  a user reads their own record; each user who is signed in reads the base
  lists; and the read of a partnership, a transfer and a partner on another
  server, which a filter holds to the refuges of the actor. An entry that
  is refused fails the test too, so the list tells no lie.
- **The test asks with `Ash.can/3`**, with no query to the database. It
  runs the policies of the action as a run does, and it needs no valid
  input, so one test covers each action. A read is refused when the
  policies forbid it, and when they give it the filter `false`. The answer
  "the record decides" counts as open, so a policy that looks only at the
  record, and not at who asks, fails the test for the stranger.
- **More tests show that the question is a fair one.** Each grant of a role
  for all records is open to that role, and a root user can run each action
  of a resource that is not closed to all. Without them, a test that
  refuses each action for a wrong reason would pass.
- **The sweep found one gap, and this ADR closes it.** AshPaperTrail makes
  a version resource for each resource with a paper trail, and it gives
  that resource no authorizer. 75 version resources were thus open: a read
  of one with any actor, or with none, in the schema of any refuge, would
  have returned the history of each record. No page and no function of
  Rescord read the versions that way: a domain reads them with
  `authorize?: false`, after the record has decided (ADR 0035). The gap was
  a door that nothing used. `Rescord.Resource` now gives each version
  resource the authorizer of the policies and
  `Rescord.Resource.VersionPolicies`, a policy that refuses each actor, a
  root user too. The functions of the domains read as before.

## Consequences

- A new action is closed until a person decides. The test fails with the
  name of the action and of the actor, and says the three ways out.
- The test does not replace the tests of the domains. It does not run an
  action, so it does not hold a scope such as "the entries that the actor
  wrote", or what a filtered read returns for real records. The tests of
  each domain hold those, and the entries of `open_on_purpose/0` name them.
- A resource that all refuges share, and that names its refuges in the
  attributes `organisation_id`, `from_organisation_id` and
  `to_organisation_id`, is asked about a record of the refuge of the test.
  A shared resource that names its refuge another way needs a line in
  `records/2` of the test.
- The sweep takes about 20 seconds, most of it for the three organisations
  of its setup.
- When an applicant or a carer becomes an actor (the adoption and foster
  records), that actor is one more line in the setup of the test.
