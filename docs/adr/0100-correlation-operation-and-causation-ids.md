# ADR 0100: A correlation, an operation and a causation id on each version

Status: accepted. P1 of ADR 0062. The maintainer chose "test first" on
28 November 2026, and the spike (report in the private repository of the
deployment, `docs/reviews/paper-trail-operation-id.md`) found that the
option works with caveats. The maintainer then chose "adopt now, the
timeline later", asked for the three ids that this ADR names, and chose
to index only the correlation id. Issue 26 is the design.

## Context

One action often writes many versions. `register` of a resident writes
the resident and each of its facts, and the removal of a resident makes
its routines forget it, drops the subjects of its tasks and skips a task
that is left with none. Before this ADR, those versions had nothing in
common but the instant, and nothing said which action caused which.

AshPaperTrail 0.8.1 has `operation_id_field`: when an action starts, it
puts a new id in `context.shared.ash_paper_trail.operation_id`, unless
one is there, and writes it on each version that the action writes. Ash
passes the shared context to a nested action and to a signal listener
that runs inline. That id is a correlation id: one for the whole piece of
work. AshPaperTrail has no id for one action call and none for its cause,
but it writes each `metadata` entity from `changeset.context`.

## Decision

Each version of a resource with a paper trail has three nullable `uuid`
columns, all UUIDs of version 7:

- **`correlation_id`**: AshPaperTrail's `operation_id_field`, the same
  for each version of one piece of work.
- **`operation_id`**: a new id for each call of an action. The change
  `Rescord.Resource.Operations.Stamp` makes it, and AshPaperTrail writes
  it as `metadata`. A transformer of `Rescord.Resource.Operations` puts
  the change first in each create, update and destroy action.
- **`causation_id`**: the `operation_id` of the action that ran this one.
  `Stamp` passes its own id on in `context.shared.rescord.operation_id`,
  and the nested action reads it there. The first action has none.

So the versions of one piece of work make a tree: the root has no cause,
and each other version names its parent.

Rules for the code:

- A change that builds the options of a nested action gives it
  `context: Rescord.Correlation.context(changeset)`, the shared context of
  its own action. Without it the nested action starts a new correlation
  and has no cause, and nothing fails. `Rescord.CorrelationTest` fails for
  a file that builds options with `tenant: changeset.tenant` and no such
  line.
- A function of a domain that runs two actions or more starts with
  `opts = Rescord.Correlation.start(opts)` and gives `opts` to each
  action: `Locations.move_location`, `Photos.keep`,
  `Photos.place_in_albums`, `Journal.write_entry_with_files` and
  `Ruby.save_provider`. Their actions share the correlation id, and each
  is a root of the tree.
- Only `correlation_id` has an index, a partial one
  (`WHERE correlation_id IS NOT NULL`), in each table with the columns. It
  answers "each version of this piece of work" over many tables. A
  timeline reads the versions of one record and groups them in memory,
  and the tree of one correlation is small, so `operation_id` and
  `causation_id` need none.

## What was tested

- `register` of a resident (7 versions), `plan_task` (2), the removal of
  a resident with its listeners, and `write_entry_with_files` with two
  photos each write one correlation id. A given id reaches each nested
  action. In the removal, the routine and the subjects name the removal
  as their cause, and the skipped task names the drop of the subjects.
- The upgrade from a database of the last release, with two
  organisations and a table of 500,200 rows: the rehearsal passed, the
  migrations added the columns and the indexes, the old rows kept no
  ids, and the next change wrote all three.
- What the index locks: `ALTER TABLE` takes `ACCESS EXCLUSIVE`, and
  `CREATE INDEX` takes `SHARE`, each until the migration of the
  organisation commits. On the table of 500,200 rows the three columns
  took about 1 ms and the index about 50 ms, and the index is 8 kB
  because no row has an id yet. The rehearsal (ADR 0081) refuses
  `CONCURRENTLY`, and the migrations run before the server answers.

## Consequences

- No page shows the ids yet. The timeline that shows one piece of work as
  one entry is a design of its own. It must fall back to the instant for
  versions from before the upgrade, and for the gaps below.
- **Gaps.** A listener that runs in a job (`AshOban.Signals`) starts a
  new correlation: the job does not keep the shared context. A destroy of
  a temporal resource with `archive?: false` (13 resources, such as
  `Placement` and `GroupMember`) writes no version, so its end has no id,
  as `Rescord.History` says already. A bulk create, and a bulk update with
  the strategy `:stream`, make a correlation id and an operation id for
  each batch of 100 records, unless the caller gives a correlation id;
  `:atomic` and `:atomic_batches` make one.
- **Two gaps that no action of today reaches** (read in the code of Ash
  3.38.1 and AshPaperTrail 0.8.1). When Ash turns an update that a caller
  built with `for_update` into an atomic one, it runs each `atomic/3`
  again and then puts the first context back: the row gets the ids of the
  second run, and an `after_action` hook or a signal of that action sees
  the ids of the first. Each update of today with a nested write is
  `require_atomic? false`, and no update emits a signal. And a record
  that `archive_related` of AshArchival archives would start a new
  correlation, because that change reads the context before AshPaperTrail
  puts the id in it; no resource sets `archive_related`. The first update
  of each kind needs a test in `Rescord.CorrelationTest`.
- `Rescord.Correlation.context/1` passes only the ids, and no other key
  of the shared context. The whole shared context would hand a nested
  action the `as_of` of its caller, and for a period that is its start:
  a nested action that wrote at the instant of the call would move.
- An older release on a migrated database moves the ids of a temporal
  record to the wrong version, with no error: a temporal update changes
  the current row in place and copies the old values to a new row, and an
  older release does not copy columns that it does not know. The upgrade
  note says so. It holds for each column that a release adds to a
  temporal table.
- Each version row is 48 bytes larger. The spike measured no difference
  in time.
