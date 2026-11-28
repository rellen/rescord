# ADR 0005: shoddy and shoddy_phoenix are dependencies, pinned to a commit

Status: accepted (chosen by the maintainer). The pins move by hand; the
section "The pins now" says where they are.

## Context

`shoddy` and `shoddy_phoenix` are the maintainer's libraries of helpers.
`shoddy_phoenix` provides the plumbing of the live widgets (ADR 0003) and the
template components `choose/1` and `switch/1`. Neither is on Hex, and
neither has a release or a tag.

## Decision

- Both come from GitHub, pinned with `ref:` to a commit, so the version
  changes only on purpose: `shoddy` at `3feca9c`, `shoddy_phoenix` at
  `acb0697`.
- `shoddy_phoenix` needs Phoenix, so only `lib/rescord_web/` and its tests use
  it. `shoddy` has no runtime dependencies, so any code may use it.
- `RescordWeb` imports `choose/1` and `switch/1` of `ShoddyPhoenix.ControlFlow`
  into every template, for three or more branches.
- `mix.exs` requires Elixir `~> 1.20`.

## Consequences

- `mix deps.get` clones both public repositories, so it needs `git` and no
  credentials.
- To update one, change its `ref:`, run `mix deps.get`, and run the checks.
  `mix hex.outdated` does not report a git dependency.

## The pins now

On 28 November 2026 `platform/mix.exs` pins `shoddy` at `d49e059` and
`shoddy_phoenix` at `5ff4a14`, the head of `main` of each. The commits
above are the first pins. ADR 0037 made a widget the exception, and no
page has one yet. So `shoddy_phoenix` runs only in the test of the
widgets, and `choose/1` and `switch/1` are imported but not yet called.
Both stay, for the first page that needs them.
