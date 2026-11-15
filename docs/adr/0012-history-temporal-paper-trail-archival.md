# ADR 0012: History comes from temporal resources, AshPaperTrail and AshArchival

Status: accepted (chosen by the maintainer)

## Context

Rescord has to answer three questions about its data:

1. What was true on a past date? For example, the name of a resident in
   March.
2. Who changed a record, when, and through which action?
3. What did a record hold before somebody removed it?

`docs/domain.md` first gave question 1 to tables in 6NF that we would write
by hand. Ash has three tools for these questions:

- **Temporal resources**, in Ash since 3.34.0 (October 2026). A temporal
  resource keeps each version of a record with the period for which it is
  valid, and each read and write happens as of one instant. The guide of Ash
  marks them experimental: "the API may change". They need PostgreSQL 18 and
  the extension `btree_gist`.
- **AshPaperTrail**, which records each change. Its default mode writes each
  version to a version resource with a table of its own. Its mode
  `:temporal_inline` puts the action, the actor and the previous values on
  each version row of a temporal resource instead.
- **AshArchival**, which turns a destroy into a mark on the row.

## Decision

- Rescord uses all three. `ash_paper_trail` and `ash_archival` are
  dependencies. `Rescord.Repo` installs `btree_gist`.
- **A fact that needs a history is a temporal resource.** It answers
  question 1. The 6NF tables of `docs/domain.md` are such resources: the key,
  the period, and one value.
- **A temporal resource keeps its paper trail inline**
  (`mode :temporal_inline`, with `change_tracking_mode :previous_values`).
  With `version_resource? true` it also gets a version resource that lists
  each version. That resource reads the same table, so it adds no table.
- **A resource that is not temporal uses the default mode** of AshPaperTrail
  where it needs a trail. That adds one resource and one table.
- **A destroy archives.** A resource that a member can remove uses
  AshArchival. On a temporal resource this also gives the removal a version
  row, which a plain temporal destroy does not write.
- **A resource with a workflow is not temporal.** See the consequences.

## What we tested

We made a resource with all three tools, in the schema of an organisation
(ADR 0011), on PostgreSQL 18.6, and then removed it. Each line is a result
that we saw:

- A record created as of January and renamed as of June reads with the old
  name as of March, and with the new name now.
- Another organisation reads no record. A read with no tenant is refused.
- The version resource lists both versions, each with its action, and the
  rename holds the previous name.
- After a removal, a read now returns no record, a read as of March still
  returns the record, and a third version holds the removal.
- A resource with AshStateMachine and `temporal` compiles, and a create
  works. A transition is refused: "AshStateMachine.BuiltinChanges.TransitionState
  is not temporal safe".

## Consequences

- AshStateMachine, AshOban and AshWorkflow declare no change as temporal
  safe. A task, which has a workflow, thus cannot be temporal. Its history
  comes from AshPaperTrail and from the transition log of AshWorkflow.
- Each change, validation and preparation that we write for a temporal
  resource declares `temporal_safe?/1`. A `before_action` or `after_action`
  hook is not temporal safe, so that logic goes in a module.
- A read of a temporal resource returns one instant. A list of each version
  comes from the version resource.
- A foreign key with a period allows no cascade in the database. We cascade
  in the application.
- An actor that authorizes a read as of a past instant is loaded as of that
  instant too.
- Temporal resources are experimental. An update of Ash can change them, so
  read the changelog of Ash before an update, and keep tests that read as of
  a past instant.
- The schema of an organisation is made with `create_tenant!/2` of
  `AshPostgres.MultiTenancy`, or with `manage_tenant`, which makes the schema
  and runs its migrations. In our test, a second call of `create_tenant!/2`
  for a schema that existed failed with a duplicate table, so call it one
  time for each organisation.
