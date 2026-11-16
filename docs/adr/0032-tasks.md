# ADR 0032: Tasks

Status: accepted (the answers are from the maintainer, 16 November 2026)

## Context

Section 5.7 of `docs/domain.md` gives an organisation its tasks. The
maintainer answered how a task becomes complete: a task is due, done or
skipped; it names a member or is for each member; and each member can take
an open task, complete it, or skip it with a reason.

`docs/domain.md` proposed that AshWorkflow holds the states of a task.

## Decision

- `Rescord.Tasks` is a domain of its own. It uses the residents, the
  locations and the journal.
- **AshStateMachine holds the states, and not AshWorkflow.** A task has one
  step, which waits for a person, and no step in the background.
  AshWorkflow is for a process of several steps (`docs/architecture.md`,
  "Signals and workflows"). The states are `due`, `done` and `skipped`, and
  a member can open a task again.
- **A task is not temporal**, because a state machine is not temporal safe
  (ADR 0012). Its history is in its paper trail, which names who made each
  change.
- **A task names what it refers to by a plain id**: its kind, its
  prescription, the member that it is for, and its subjects. The database
  holds no key from a table with no period to one with a period.
- **`TaskSubject` is one resource** for the three things that a task can be
  for: a resident, a group or a location. A check constraint holds that a
  record names one of them. The estimate of `docs/domain.md` had a resource
  for each.
- **A task for a member does not stop another member.** The member that a
  task names is who is expected to do it. Each member can complete it.
- **A task that names a prescription writes a dose.** When a member
  completes it, Rescord writes a journal entry of the kind `dose` for the
  resident of the prescription, as that member. A fault in the entry stops
  the completion. A member plans such a task from the prescription, on the
  journal page. No kind of task has this rule: the list of kinds is one
  that an organisation can extend, so a name in it means nothing to the
  code.
- **The page shows one day**, in the time zone of the organisation, with the
  tasks of earlier days that are still due on the page of today. A task is
  overdue when it is due and its time is before now. A member can plan a
  task for any day.
- Each member has each grant here. The kind of a task is the last but one
  list that an organisation can extend.

## Consequences

- A task that is planned for a resident stays when the resident leaves.
  Nothing cancels it.
- A task has no reminder. When it gets one, the step in the background is
  a reason to look at AshWorkflow again.
- The routine of section 5.7, which makes tasks from a pattern, is the next
  step. A task has no link to a routine yet.
- The page has no view of a week or a month. A member moves one day at a
  time, or gives the day in the address.
