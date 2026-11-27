# ADR 0062: Where signals, AshWorkflow, AshEvents, AshPaperTrail and AshBoundary fit

Status: proposed (the maintainer asked on 28 November 2026: "are we making
good use of Ash signals and AshWorkflow? AshEvents? AshPaperTrail?", and
then "what about AshBoundary?"). This is an assessment. It changes no code.
The maintainer chose proposals B1, S1 and S3 on 28 November 2026: ADR 0066
is B1, and ADR 0067 is S1 and S3. The other proposals wait for the
maintainer.

## Context

`docs/architecture.md`, "Signals and workflows", says that Rescord uses Ash
signals and AshWorkflow where they fit, before it writes the same thing by
hand. ADR 0009 gave each domain a boundary, ADR 0010 installed AshWorkflow
and Oban, and ADR 0012 gave each resource its history. Nobody had looked at
the code as a whole to see how much of this it uses.

This ADR read the code of each domain, and the source and the guides of the
packages at the versions of `platform/mix.lock`, and not from memory:

| Package | Locked | Newest on Hex | In Rescord |
| --- | --- | --- | --- |
| `ash` (signals are a part of it since 3.36.0) | 3.38.1 | 3.38.1 | signals: not used |
| `ash_workflow` | 0.13.0 | 0.13.0 | installed, not used |
| `ash_oban` (has `AshOban.Signals`, a delivery of signals in jobs) | 0.10.3 | 0.10.3 | starts Oban, no trigger |
| `ash_paper_trail` | 0.8.1 | 0.8.1 | each resource |
| `ash_boundary` | 0.2.0 | 0.2.0 | each domain |
| `boundary` | 0.10.4 | 0.12.0 | `ash_boundary` asks for 0.10 |
| `ash_events` | not a dependency | 0.8.2 (18 September 2026) | not used |

## The answer in short

| Tool | How well Rescord uses it | What to do |
| --- | --- | --- |
| AshPaperTrail | Well. It is a default of `Rescord.Resource`, in the right mode for each kind of resource. | One addition to look at: an operation id (P1). |
| AshBoundary | Well, and strictly. One open question of ADR 0009 can close now. | Turn on the check of aliases (B1). |
| Ash signals | Not at all. Three gaps that our own ADRs record are what a signal is for. | Start with the removal of a resident (S1). |
| AshWorkflow | Not at all, and that is right for the code of today: no process has a step in the background or a deadline. | Use it for the first process that has one (W1 to W4). |
| AshEvents | Not a dependency, and it should stay so. | Nothing. |

## What we tested

We tried the first signal in a copy of the repository, with PostgreSQL 18,
and then threw the copy away. Each line is a result that we saw:

1. **An `emit` on a temporal resource is refused in Ash 3.38.1.** With
   `emit Rescord.Residents.Signals, :resident_removed, fields: [resident_id: :id]`
   on `Resident.remove`, the action returns `Ash.Error.Framework`:
   "Ash.Resource.Change.EmitSignal is not temporal safe". The change that
   `emit` adds does not declare `temporal_safe?/1`. Most resources of
   Rescord are temporal, so this stops each signal that they emit.
2. **One line of configuration makes it work.**
   `config :ash, :temporal_safe_modules, [Ash.Resource.Change.EmitSignal]`
   is what the guide of temporal resources gives for a module of a package.
   Ash reads it when it compiles. With it, the removal of a resident ended
   the placement of that resident, through a listener on
   `Rescord.Locations.Placement`
   (`on :resident_removed, :finish_of_removed, action: :finish, get_by: [resident_id: :resident_id]`),
   in the schema of the organisation and as the administrator.
3. **A listener writes at the instant of the action that emitted.** A
   removal as of an instant two days from now left the placement as of the
   day before, and ended it as of the day after. The instant travels in the
   shared context, which a listener gets.
4. **The compilers `:boundary` and `:ash_signals` work together.** A full
   compile with `--warnings-as-errors` passed. The modules that signals
   generate (`Ash.Signals.Listeners.*`, `Ash.Signals.Index.*` and
   `Ash.Signals.Dispatch.*`) are outside each boundary, and `boundary`
   0.10.4 gives no warning for them.
5. **The boundaries do not see a signal today.** A listener names its
   signal module as an alias, and no domain checks aliases. The compile
   passed with the signal module internal to `Rescord.Residents`. With
   `check [aliases: true]` on each domain, the compiler refused it until
   the domain exported the module.
6. **`check [aliases: true]` on each domain gives 17 other warnings, and
   all of one kind**: a relationship to one of the 15 list resources of
   `Rescord.Lists` (`Species`, `Unit`, `TaskKind` and so on), which have no
   `define` and so are internal. No warning was for a domain that is
   missing from `deps`.

We did not test: a listener that runs in a job (`AshOban.Signals`), a
workflow in the schema of an organisation, the operation id of
AshPaperTrail on a temporal resource, and a listener whose actor has no
grant for the action of the listener.

## AshPaperTrail

**It is used as it should be.** `Rescord.Resource`
([resource.ex](../../platform/lib/rescord/resource.ex)) gives each resource
a trail: on the version rows of a temporal resource (`:temporal_inline`,
with the previous values), and in a version resource for a resource with a
state machine. Each domain includes the versions, `Rescord.History` reads
them as changes (ADR 0035), the resources that hold keys and tokens have no
trail, and a large or noisy attribute is left out (`ignore_attributes`,
`ignore_actions`).

| | Current code | Proposal | Benefit | Effort | Risk |
| --- | --- | --- | --- | --- | --- |
| **P1** | One action often writes many records: `Resident.register` writes each fact, `Task.complete` writes a dose, a removal ends the ties. Their versions have nothing in common but the instant. | Set `operation_id_field` in `Rescord.Resource`. AshPaperTrail then stamps each version with the id of the action call that caused it, and passes the id to nested actions in the shared context, which a signal listener gets too, so its versions should carry the same id. | The timeline can show "one thing that a member did" as one entry, and a reaction in another domain is tied to its cause. | Medium: one line, then a column in each table of each organisation. | Not tested in the mode `:temporal_inline`. Worth doing with, or just before, the first signal. |

`Rescord.History` notes that the versions do not say who ended a record.
An operation id does not change that.

## AshBoundary

**It is used well.** Each of the nine domains declares its boundary with
`AshBoundary`, the core and the web layer are boundaries by hand with
`check: [aliases: true]`, the web layer cannot call `Ash`, and a broken
rule fails the gate. The `deps` make an order with no cycle, in which a
domain uses only domains to its left:

    Accounts, Lists, Residents, Locations, Journal, Photos, Transfers

    Tasks uses Accounts, Lists, Residents, Locations and Journal
    Inventory uses Accounts, Lists and Locations

| | Current code | Proposal | Benefit | Effort | Risk |
| --- | --- | --- | --- | --- | --- |
| **B1** | No domain sets `check [aliases: true]` (an open question of ADR 0009 and of `docs/architecture.md`). A relationship, and a signal listener, can name an internal module of any domain, in `deps` or not. | Set `check [aliases: true]` in the `boundary` block of each domain, and give each of the 15 list resources of `Rescord.Lists` a `define`, which makes it public. | The rule "a domain uses only what another domain exports" then holds for relationships and for signals too, and not only for calls. | Small: nine lines and 15 defines (test 6). | Low. A `define` publishes the whole module of a list resource, which each domain already names in a relationship. |
| **B2** | `docs/architecture.md` asks where a signal module that two domains share lives. | It lives in the domain that emits, as `Rescord.<Domain>.Signals`, in the `exports` of that domain. A domain that listens names the emitting domain in `deps`. | No new boundary. For a signal that goes up the order above, the listener depends on the emitter already: Locations, Journal, Tasks, Photos and Transfers all use Residents. A listener in another direction adds one entry to its `deps` (S4). | None beyond each signal. | A cycle comes only when the emitter already depends on the listener. A call is legal then, so a signal is less necessary (see S5). |
| **B3** | `boundary` is 0.10.4, and the newest is 0.12.0. | Nothing now. `ash_boundary` 0.2.0, its newest version, asks for 0.10. | | | Look again when `ash_boundary` allows a newer one. |

One thing that the boundaries cannot see: `docs/architecture.md` says that
changes reach the pages through `Ash.Notifier.PubSub`, which the widgets
subscribe to. No resource has a notifier, and no widget subscribes, so a
page does not hear a change that another member made. That is not the work
of a signal (a signal runs in the transaction; a page hears after the
commit), and it is outside this ADR, but the document and the code
disagree.

## Ash signals

**A signal is for one case: a domain must react to an action of a domain
that cannot know it.** Rescord has that case each time a domain low in the
order above changes something that a higher domain refers to. A call cannot
do it, because the low domain may not use the high one. Our ADRs record the
gaps that this left:

- ADR 0036: "A removed resident keeps its placement row", and the housing
  leaves out a placement that it cannot read.
- ADR 0032: "A task that is planned for a resident stays when the resident
  leaves. Nothing cancels it."
- ADR 0033: "A routine keeps a resident, a group or a location that is not
  there any more."

| | Current code | Proposal | Benefit | Effort | Risk |
| --- | --- | --- | --- | --- | --- |
| **S1** The removal of a resident | [`Resident.remove`](../../platform/lib/rescord/residents/resident.ex#L49) runs [`EndTies`](../../platform/lib/rescord/residents/changes/end_ties.ex), which ends the ties inside Residents. The placement, the task subjects and the routines keep the resident. | `Rescord.Residents.Signals` with `:resident_removed`, and an `emit` on `remove`. `Placement` listens and finishes the placement. `TaskSubject` and `Routine` listen and drop the resident. `EndTies` stays: it is in the same domain. | Closes the three gaps above, in the transaction of the removal: a fault in a listener undoes the removal. No new entry in `deps`. | Medium. The part for the placement is what we tested. | The line of configuration of test 2. Each listener action needs a policy line (see below). What a task with no subject left should do is a question for the maintainer. |
| **S2** A departure | [`Departure.record`](../../platform/lib/rescord/residents/departure.ex#L16) writes the departure. Locations and Tasks have no code that reads a departure: the resident keeps its placement, its tasks stay due, and its routines make more. | `:resident_departed`, with the same listeners as S1 where the maintainer wants them. | A resident that left takes no place in the housing and gets no new tasks. | Medium, small after S1. | It changes what members see, so the maintainer decides what a departure ends. A member can withdraw a departure, and the listeners do not undo themselves. |
| **S3** The email of an invitation | [`Invite`](../../platform/lib/rescord/accounts/changes/invite.ex#L30) sends the email in an `after_transaction` hook. A fault goes to the log, and nothing sends it again. | `:member_invited`, and a listener that sends the email with `delivery: {AshOban.Signals, queue: :default}`. The job is written in the transaction of the invitation, runs after the commit, and Oban tries it again after a fault. | An invitation whose email met a mail server that was down still arrives. | Small to medium. | The first use of a signal in a job: the job runs with no actor unless we add an actor persister. A plain Oban job does the same with no signal. The request for a sign-in link stays as it is (ADR 0019). |
| **S4** Stock below a reorder level | [`Inventory.stock/1`](../../platform/lib/rescord/inventory.ex#L201) finds it when a member opens the page. Nothing happens when a movement takes the stock below the level. | `Rescord.Inventory.Signals` with `:stock_short`, emitted from the change that records a movement (`dynamic?: true`, because the level is a sum). `Tasks` listens and plans a task to order more. | The refuge learns that an item runs out with no look at the page. | Medium. | A new behaviour, so the maintainer decides it. `Tasks` gets `Rescord.Inventory` in its `deps`. The emit must fire only when a movement crosses the level. |
| **S5** The dose of a task | [`WriteDose`](../../platform/lib/rescord/tasks/changes/write_dose.ex#L18) calls `Journal.write_entry` after the completion of a task with a prescription. | Keep the call. | Tasks may use Journal, the entry needs a read of the prescription first, and its fault must stop the completion. A signal adds nothing here. | None. | Look again when a second domain reacts to a completed task, for example a dose that takes stock (`docs/domain.md` says that it does not today). |
| **S6** The answer to a transfer | [`Transfer.accept`](../../platform/lib/rescord/transfers/transfer.ex#L83) changes the state. The refuge that sent records the departure by hand, and the refuge that received has a copy and no resident (ADR 0042). | Later: `:transfer_accepted`, for a task at the sender to record the departure, and for "register a resident from a copy". | It ties the two halves of a transfer together. | Medium to large. | A transfer is outside the schemas, so the emit must give the tenant of the listener (`Ash.Signals.emit/5` with `tenant:`). ADR 0042 chose the manual step with intent. |

**Rules that the first signal needs**, which would go in `AGENTS.md`:

- `mix.exs` gets the compiler `:ash_signals`, after `:boundary`, and the
  endpoint gets it in `reloadable_compilers`.
- `config/config.exs` gets the line of test 2, with the reason, until Ash
  declares the change temporal safe. That is a fault to report to Ash.
- A listener runs as the actor of the action that emitted. That person
  often has no grant for the action of the listener, and should not need
  one. The policy of such an action gets
  `authorize_if signal_in(Rescord.Residents.Signals, :resident_removed)`
  before the check `Granted` (it adds to ADR 0021).
- A listener is inline when its write must commit with the action, and in a
  job (`AshOban.Signals`) when it calls a service outside Rescord.
- `mix ash.signals --format mermaid` draws what emits and what listens. The
  drawing can go in `docs/`.

## AshWorkflow

**No process of today needs it, so "installed and not used" is the right
state, and not a debt.** AshWorkflow pays for itself when a process has a
step in the background, a deadline, a reminder or a log of its transitions.
Each state of a task, a transfer and a partnership waits for a person,
which is what ADR 0032 found for the task. Version 0.13.0 has grown since
ADR 0010: it emits and receives signals (`emit`, `on_signal`), fires at an
instant of the record (`fire_at`), repeats (`every`), refuses a transition
from an old copy with no filter written by hand, keeps a log of transitions
with an undo, and ships recipes (approval, review, verification, expiry).

Two limits hold for each candidate. A resource with a workflow is not
temporal (ADR 0012). And a trigger of AshOban for a resource in the schema
of an organisation must list the tenants: AshOban has `list_tenants` for
that, the scheduler of AshWorkflow does not set it, and we did not test it.

| | Current code | Proposal | Benefit | Effort | Risk |
| --- | --- | --- | --- | --- | --- |
| **W1** Adoption and foster records | Not written. They are in the scope of `docs/domain.md`. | Design them as a workflow from the first day: an application, checks, a decision, a placement, and visits after it, each with its deadline. | This is the first process of Rescord with several steps and deadlines. The recipes for an approval and a review are close to it. | Part of that feature. | The first workflow in the schema of an organisation: test `list_tenants` first. |
| **W2** A transfer and a partnership with no answer | [`Transfer`](../../platform/lib/rescord/transfers/transfer.ex#L83) and [`Partnership`](../../platform/lib/rescord/transfers/partnership.ex#L51) hold a state in a plain attribute, with a filter and a `set_attribute` in each action. A question with no answer waits for ever (ADR 0042). | Only if the maintainer wants a reminder or an end for a question with no answer: a workflow with `timeout :remind` and `timeout :expire`. | The deadline is declared, the filters go, and the transitions get a log and a drawing. Both resources are outside the schemas, so no tenant is in the way. | Medium. | With no deadline, the gain is too small to change code that works. |
| **W3** A reminder for a task | [`Task`](../../platform/lib/rescord/tasks/task.ex#L55) uses AshStateMachine. ADR 0032: "A task has no reminder. When it gets one, the step in the background is a reason to look at AshWorkflow again." | When a task gets a reminder: `timeout :overdue, fire_at: :due_at`. | The reminder is one line, and the filters on the state go. | Medium. | Rescord has no channel for a reminder but the email of a sign-in. That decision comes first. |
| **W4** The job of the routines | [`GenerateTasks`](../../platform/lib/rescord/tasks/workers/generate_tasks.ex) is an Oban worker by hand that runs each hour for each organisation, and [`Routine`](../../platform/lib/rescord/tasks/routine.ex#L96) has a boolean `paused`. | Keep it. A workflow (`running` and `paused`, with `every`) or an AshOban trigger could replace the worker. | Small: the worker is 36 lines and it works. | | A change here costs more than it gives. |

## AshEvents

**Do not add it.** AshEvents writes each action to one event log, and can
build the state again from the log. For Rescord:

- **It answers questions that have an answer.** "Who changed what, and
  through which action" is AshPaperTrail. "What was true on a past date" is
  the temporal resources, which a read as of an instant answers in SQL. The
  README of AshEvents says that AshPaperTrail stores more, and shows past
  versions better.
- **A replay has no use here.** A replay clears the records and runs each
  event again. The history of Rescord is the version rows, and they are
  the truth already.
- **It is likely not to work with a temporal resource.** AshEvents turns
  each action that it tracks into a manual action, and calls the data layer
  itself. The guide of temporal resources says that a manual action skips
  the temporal handling. AshEvents 0.8.2 is from September 2026, before
  temporal resources, and does not name them. We did not test it.
- **Tenancy.** Its log is one resource. It knows tenancy by an attribute,
  and Rescord has a schema for each organisation.

If another system must hear what happens in Rescord one day, a signal with
a listener in a job is the smaller step: the signals are typed, each one
has an id, and Ash sends a telemetry event for each. Look at AshEvents
again only if the maintainer wants to build the state from events.

## The order that we propose

1. **B1**, the check of aliases. It is small, and it makes the boundaries
   hold for the signals that follow.
2. **S1**, the removal of a resident, as the first signal, with the rules
   above in `AGENTS.md` and `docs/architecture.md`. Report the fault of
   test 1 to Ash.
3. **S2**, a departure, after the maintainer says what a departure ends.
4. **S3**, the email of an invitation, as the first signal in a job.
5. **P1**, the operation id, when the timeline should show a reaction with
   its cause.
6. **W1**: design the adoption and foster records as the first workflow.
7. **S4**, **S6**, **W2** and **W3** are new behaviour. Each waits for a
   decision of the maintainer on what Rescord should do.

S5, W4, B3 and AshEvents: no change.

## Consequences

- Nothing changes until the maintainer chooses. Each proposal that is
  built gets its own ADR, or adds to the one that it changes (ADR 0009 for
  B1, ADR 0036 for S1).
- `docs/architecture.md` keeps its two open questions until B1 and B2 are
  accepted. This ADR gives a tested answer for each.
- Until Ash declares `Ash.Resource.Change.EmitSignal` temporal safe, each
  signal of a temporal resource depends on one line of configuration that
  Ash reads at compile time. An update of Ash can make the line
  unnecessary, and the tests of the first signal will say if it breaks.
