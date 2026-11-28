# ADR 0086: A pipeline for the lines that actions of one resource share

Status: accepted for the rule and for `Expense` (the maintainer asked on
28 November 2026: "are we using Ash pipelines to clean up action
declarations?"). The maintainer chose proposal P2 on 28 November 2026, and
it is built. Proposal P1 waits for the maintainer. Issue 18 holds the
assessment.

## Context

A pipeline is a part of Ash since 3.23.0 (31 March 2026), and Rescord
locks 3.38.1. A resource names a group of lines one time, and an action
takes the group:

```elixir
pipelines do
  pipeline :checked_facts do
    validate {Accounts.Validations.NotAfterToday, attribute: :incurred_on}
    validate Validations.CategoryOfOrganisation, before_action?: true
  end
end

actions do
  create :submit do
    pipe_through [:checked_facts]
  end
end
```

The source of 3.38.1 (`Ash.Resource.Transformers.ResolvePipelines`) gives
the limits:

- A pipeline holds `change`, `validate` and `prepare` lines, and nothing
  else: no argument, no `accept`, no `require_atomic?`, no `emit` of a
  signal.
- A pipeline belongs to one resource, and it takes no parameter.
- Ash puts the lines in the action at compile time, at the place of the
  `pipe_through`. The action that runs is the same as one with the lines
  written in it.
- **Inside one pipeline, each change comes before each validation**, in
  whatever order the pipeline writes them. A create, an update and a
  destroy take the changes and the validations, and a read and a generic
  action take the preparations and the validations.

Rescord used no pipeline. This ADR read each action from Ash after a
compile, with the version resources left out: 88 resources, 406 actions,
and 377 changes, validations and preparations in those actions.

## The answer in short

No, and there is little for a pipeline to take.

- Five resources have two actions that share a run of two or more lines in
  the same order: `Expense`, `JournalEntry`, `Role`, `Task` and
  `Ruby.Provider`. One group is in three actions: the three validations of
  the facts of an expense, in `submit`, `record` and `revise`.
- The repetition that Rescord has is of kinds that a pipeline cannot hold.
  41 of the 125 arguments repeat an argument of another action of their
  resource: the 13 arguments of the medical facts are in `write` and in
  `correct` of a journal entry. 53 actions say `require_atomic? false`. 58
  of the 88 resources have the same policy, and about 25 files write its
  nine lines.

## Decision

- **A pipeline holds a group of changes and validations that actions of
  one resource must keep the same, when the group has three lines or more,
  or when three actions or more take it.** A smaller group stays in its
  actions: a pipeline of two lines for two actions adds four lines and a
  place to look, and takes four lines off.
- **A pipeline never changes the order of the lines.** A group with a
  validation before a change is not one pipeline. Write it as it is, or as
  two pipelines when each passes the rule.
- **A pipeline has a name that says what the group is for, and a
  `description`.** The section `pipelines` stands before `actions`
  (`config :spark, formatter:` holds the order).
- **`Expense` has two pipelines**: `:new_expense`, the author, the amount
  and the payer of the two create actions, and `:checked_facts`, the three
  validations of the facts in `submit`, `record` and `revise`. A fourth
  rule about the facts of an expense now has one place.
- **A move to a pipeline is shown to change nothing.** A script wrote each
  action of each resource as Ash compiled it, with the line numbers taken
  off, before the change and after it: the 519 actions, with those of the
  version resources, are the same text.

## What stays as it is

- **`JournalEntry`, `write` and `correct`** share two validations and then
  two changes. One pipeline would run the two changes first, and
  `LinkEpisode` writes a condition before the action. Two pipelines of two
  lines do not pass the rule.
- **"Filter on the state, set the state, one change"** is in `Transfer`,
  `Partnership`, `Task` and `Expense`. The line in the middle is another
  one in each action, and a pipeline takes no parameter.
- **`Role`, `Task` and `Ruby.Provider`** share two lines in two actions.
- **The arguments and `require_atomic? false`.** Ash has no group for
  them. A macro would hide what an action takes from the person who reads
  it, and each `require_atomic? false` is a decision about its own action.

## Proposals that wait for the maintainer

- **P1. The policy of the grants as a default of `Rescord.Resource`.** The
  bypass for a root user and `authorize_if Rescord.Accounts.Checks.Granted`
  are the policy of 58 resources. An option such as `policy: :grants`
  would write them, with the authorizer, and a resource with another
  policy would write its own as today. For: a change to that policy, such
  as a new kind of actor, is in one place and not in 25 files. Against: a
  person who reads a resource no longer sees its policy in it, and this is
  the part of a resource that a review reads first. The sweep of ADR 0063
  holds in both cases.
- **P2. One `SetAuthor` and one `NotAfterToday`. Built.** `Expenses`,
  `Journal` and `Photos` each had a `SetAuthor` with the same body.
  `Expenses`, `Photos` and `Residents` each had a `NotAfterToday`, and the
  three found today in three ways. Now `Rescord.Accounts.Changes.SetAuthor`
  and `Rescord.Accounts.Validations.NotAfterToday` are the only ones, and
  `Rescord.Accounts` exports them as it exports `Checks.Granted`: both
  need the user and the time zone of the organisation, which are of that
  domain. The validation takes the date as the option `:attribute`. Today
  is the date at the instant of the action when the action has one, and
  else by the clock, which is what each of the three did for its own
  resources. One thing differs: when the caller gives the organisation as
  a record, the validation of an expense and of a photo now reads the time
  zone from that record, as the one of a resident did, and makes no query
  for it. The compiled actions are the same but for the names of the two
  modules and the new option of the photo.

## Consequences

- No behaviour changes, no migration, and no new dependency.
- A person who reads an action with `pipe_through` looks at the section
  above it for the lines. The rule keeps that cost for the groups where a
  forgotten line in one action is the larger risk.
- The rule is in `AGENTS.md`. A new resource with a state machine, such as
  the adoption records, is the likely next case.
- The numbers above are of 28 November 2026. A check that finds a group
  that passes the rule is not written: Ash leaves no trace of a pipeline
  in a compiled action, so the check would read line numbers.
