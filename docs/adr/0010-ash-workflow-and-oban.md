# ADR 0010: AshWorkflow is installed, and Oban with it

Status: accepted (asked for by the maintainer)

## Context

The architecture says that we use AshWorkflow for a process of several
steps, in place of a state machine and jobs written by hand. AshWorkflow
generates the states of `ash_state_machine` and the triggers of `ash_oban`,
so it needs Oban in the supervision tree, a queue, and Oban's table.

## Decision

- `mix igniter.install ash_workflow` installed `ash_workflow` 0.12, and with
  it `ash_state_machine`, `ash_oban` and `oban` as dependencies of the
  project.
- Oban is configured in `config/config.exs`: the queues `default` and
  `workflow`, each with a limit of 10, the cron plugin with no entry, the
  pruner, which keeps a finished job for one day, and the lifeline, which
  rescues a job stuck for two hours. The triggers that AshWorkflow generates
  publish to `workflow`.
- `Rescord.Application` starts Oban with `AshOban.config/2` over the
  domains of `:ash_domains`. It starts after the repo, which holds the jobs,
  and after PubSub, so that a job can publish. The installer had put it
  before PubSub.
- In tests Oban runs no job by itself (`testing: :manual`).
- The migration `add_oban` creates Oban's table. `mix ash.setup` runs it.
- A workflow is declared on a resource with
  `extensions: [AshWorkflow, AshOban]`. `AshStateMachine` is not named there:
  AshWorkflow adds it.

## Consequences

- `ash_domains` is in the configuration, and it is empty. A new domain is
  added to it, or Oban gets no trigger from that domain.
- The installer added `ash_state_machine`, `ash_oban` and `oban` to
  `mix.exs`. The README of `ash_workflow` says not to declare the first two
  yourself. We kept what the installer wrote, because `Rescord.Application`
  names `Oban` and `AshOban` directly.
- The installer failed on its first run, in `ash.install`, which it runs
  again: `Rewrite.DotFormatter` raised `CaseClauseError` on `:hmac`, at the
  keyset signing secret that `config/runtime.exs` already held. With that
  block taken out, the installer ran, and wrote the block again exactly as
  it was. The fault is upstream, and another installer that runs
  `ash.install` again will meet it.
- That second run of `ash.install` also wrote new keyset signing secrets
  for dev and test. We kept the old ones.
- Checked: Oban starts with both queues and the three plugins, the
  migration runs, `mix ash.codegen --check` finds nothing to generate, and
  the gate passes.
- There is no workflow yet, and no resource. The first one needs
  `mix ash.codegen` for its `state` and `state_entered_at` attributes.
