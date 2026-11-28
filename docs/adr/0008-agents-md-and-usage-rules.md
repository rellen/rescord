# ADR 0008: AGENTS.md holds the conventions, and usage_rules links the rules of the dependencies

Status: accepted (asked for by the maintainer); amends ADR 0004

## Context

ADR 0004 removed the `AGENTS.md` that `mix phx.new` generates, because it
told agents to use Tailwind, and put the project's conventions in
`CLAUDE.md`. That had two costs. `CLAUDE.md` is the file of one tool, where
`AGENTS.md` is the name that agents share. And the generated file had also
carried the usage rules of Phoenix, so an agent lost the guidance that the
authors of Phoenix and Ash write for their packages.

The package `usage_rules` gathers the `usage-rules.md` files that
dependencies ship, and writes them, or links to them, into a file. Seven of
our dependencies ship rules: `ash`, `ash_phoenix`, `ash_postgres`, `igniter`,
`phoenix`, `reactor` and `spark`. Together they are about 114 kB, which is
too much to put inline.

## Decision

- `CLAUDE.md` is renamed to `AGENTS.md`, at the repository root. It holds
  Rescord's conventions, written by hand. There is no `CLAUDE.md`.
- `usage_rules` is a dependency, for `:dev` only. Its configuration is the
  `usage_rules` key of `platform/mix.exs`.
- `mix usage_rules.sync` writes `platform/AGENTS.md`. It puts inline the
  rules of `usage_rules` itself (how to search the documentation of a
  package) and its built-in rules for Elixir and OTP, and it writes a link
  to the rules of every other dependency that ships them. A regex selects
  those, so a new dependency with rules gets its links at the next sync.
- The generated file is inside the Mix project, and not the root file,
  because the task writes each link relative to the Mix project
  (`deps/ash/usage-rules.md`). We tried `file: "../AGENTS.md"`: the task
  wrote the root file, with links that lead nowhere from there.
- The root file wins. `platform/AGENTS.md` starts with a hand-written part
  that says so, which the task keeps. The known differences are the Tailwind
  classes and the `hero-` icon names in the examples of the Phoenix and
  AshPhoenix rules, and "avoid LiveComponents unless", where our rule is
  "no LiveComponents".

## Consequences

- Run `mix usage_rules.sync` after a change to the dependencies, and commit
  the result. Nothing checks that the file is current: the task needs the
  `:dev` environment, and `mix precommit` runs in `:test`.
- The links lead into `deps/`, which git ignores, so they work after
  `mix deps.get` and not on GitHub.
- Claude Code reads `AGENTS.md` when a directory has no `CLAUDE.md`, from
  version 2.1.277, and it reads the file of a subdirectory when it opens a
  file there. If a session does not pick the file up, add a `CLAUDE.md` that
  holds the one line `@AGENTS.md`.
- `shoddy` and `shoddy_phoenix` ship no usage rules. Writing them is a
  pattern to give back to those libraries. (Both ship them since 15
  November 2026, and `platform/AGENTS.md` links them.)
