# ADR 0013: Each resource uses Rescord.Resource

Status: accepted (asked for by the maintainer)

## Context

ADR 0011 and ADR 0012 give each resource the same set of decisions: the
data layer, the schema of an organisation, a temporal section, a paper trail
in the mode that fits, and a destroy that archives. Written out in each of
about 44 resources, those sections would differ by accident. One rule also
needs a check: a resource cannot be temporal and have a workflow, and such a
resource compiles and then fails when a transition runs.

Ash describes a base resource for this: a module with a `__using__` macro
that wraps `use Ash.Resource`.

## Decision

- `Rescord.Resource` is the base of each resource. A resource writes
  `use Rescord.Resource, domain: ...` in place of `use Ash.Resource`.
- Its defaults are: `AshPostgres.DataLayer` with `Rescord.Repo`; the schema
  of an organisation; temporal, with the period in `:valid_at`; a paper trail;
  and a destroy that archives.
  - On a temporal resource the paper trail is `mode :temporal_inline`, with
    `change_tracking_mode :previous_values`, the action name, and a version
    resource that lists the versions.
  - On any other resource the paper trail is the default mode, with
    `change_tracking_mode :changes_only` and the action name.
- Four options change a default, each a literal `true` or `false`:
  `temporal?`, `paper_trail?`, `archive?` and `shared?`. `shared?: true` is
  for a resource that all organisations share.
- A section that a resource writes again adds to the defaults.
- `Rescord.Resource.Checks` is an extension that each resource gets. Its
  check `TemporalOrWorkflow` stops the compile of a resource that is temporal
  and uses AshStateMachine or AshWorkflow. Such a resource states
  `temporal?: false`, so the exception is in the resource for a reader to
  see.
- The check is a Spark transformer that changes nothing. Spark reports the
  error of a verifier as a warning, and this rule must stop the compile.
- `config :rescord, base_resources: [Rescord.Resource]` names the base to
  Ash, and the formatter configuration of Spark names it as a resource with
  its extensions.
- `Rescord` exports `Rescord.Resource` and `Rescord.Resource.Checks`, so that
  a domain with `deps [Rescord]` can use them (ADR 0009).

## Consequences

- A resource states its table, its attributes, its actions and its
  relationships, and no more.
- A domain adds `AshPaperTrail.Domain` to its extensions, with
  `include_versions? true`, because the version resources belong to it.
- The paper trail names no actor yet, because there is no member resource.
  When there is one, `Rescord.Resource` adds `belongs_to_actor`.
- A dimension that all organisations share uses `shared?: true`.
- `Rescord.ResourceTest` reads the defaults from resources as they compiled.
  With the check taken out, its test for a temporal resource with a workflow
  fails.
- We also made a resource of twelve lines with this base, in a domain with
  AshBoundary, and ran it on PostgreSQL 18.6: it compiled with warnings as
  errors, and reads as of a past instant, the version list, the removal and
  the isolation between organisations all worked.
