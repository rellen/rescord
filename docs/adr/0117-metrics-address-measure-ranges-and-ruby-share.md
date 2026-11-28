# ADR 0117: The address of the metrics, the ranges of the measurements, and a share of Ruby

Status: accepted (28 November 2026). The security review of ADR 0115 left
three items for a decision. The maintainer chose to design all three
(issue 41), and then to build them with the nine judgement calls of the
issue as written. This record grows with each of the three parts.

## The address of the metrics

### Context

`RESCORD_METRICS_PORT` turns the metrics on (ADR 0077). They listened on
the address of the pages, `RESCORD_LISTEN_ADDRESS`, which is `0.0.0.0` by
default. The metrics have no sign-in and no TLS. `docs/self-hosting.md`
said not to publish the port, but a host with no firewall in front, a
container with the port mapped to each address, or a proxy that forwards
each port published it. The metrics name no person and no organisation,
but they give the routes, the counts and the times of the server to
anyone who asks.

### Decision

- **`RESCORD_METRICS_ADDRESS`**, a variable of the environment, is the
  address that the metrics listen on, `127.0.0.1` by default. `0.0.0.0`
  fits a collector in the network of a Compose file, and `::` or a
  private address a platform that reads the machine over its private
  network. `docs/self-hosting.md`, "The metrics", has a table of the
  three.
- **A wrong address stops the start** with the name of the variable, as
  `RESCORD_LISTEN_ADDRESS` does. An address is no secret, so the message
  gives the value too, as the message of `RESCORD_LISTEN_ADDRESS` does.
- **`bin/check` says where the metrics listen** (`Rescord.Release.Check.metrics/1`):
  a note when they are off, ok on a loopback address, and a note on any
  other address, to keep the port inside the network of the server.
- **It stays a variable of the environment, and is not a setting of a
  root user** (judgement call 9 of issue 41). ADR 0068 keeps the
  environment for what Rescord needs before the database, before the
  first sign-in, or what describes the machine. The address describes the
  machine and its network, as `RESCORD_LISTEN_ADDRESS` and
  `RESCORD_METRICS_PORT` beside it do, and the listener of the metrics
  starts in `RescordWeb.Telemetry`, before `Rescord.Repo`, so that a
  collector still reads a server whose database is down. A setting in the
  database would leave the metrics off until the database answers.
- **An address and not a token** (judgement call 8). A token is a secret
  to keep and to rotate, and Prometheus and the scrapers of platforms
  take an address more easily than a header.

### Consequences

- The metrics are not in a release yet (they are under "Unreleased" in
  `CHANGELOG.md`), so the new default breaks no server that runs a
  release. A server that runs `main` with a collector on another machine
  sets `RESCORD_METRICS_ADDRESS` before its next start, or the collector
  reads nothing.
- In a container, `127.0.0.1` is the container itself, so a collector
  outside it needs `0.0.0.0` with the port published to the machine
  alone.

## The ranges of the measurements

### Context

A measurement took any decimal (`Rescord.Journal.Measurement`, `value`).
A weight of `-5 kg`, `0 g` or `1095 kg` for a kitten was stored, charted
and exported. A mistake of the unit (kg for g) is the most likely error,
and a chart then shows a jump of a thousand times. The measure kinds are
values that each organisation names, so Rescord cannot know the right
range of a kind.

### Decision

- **A rule that always holds** (`Rescord.Journal.Validations.Value`, on
  `write` and `correct`): a measurement in a unit of mass, length or
  volume is more than 0. A temperature can be below 0 in Celsius, and a
  count or a score can be 0, so the other units, and a unit that Rescord
  does not know, have no such rule (judgement call 6).
- **A range that the organisation gives**: `lowest` and `highest` of
  `Rescord.Lists.MeasureKind`, decimals, both optional, in the standard
  unit of the kind. The action `set_range` has the grant of
  `set_standard_unit`, and `Rescord.Lists.Validations.Range` refuses a
  range with no standard unit (judgement call 7) and a lowest above the
  highest. The page Lists has the two fields under the standard unit.
- **The check** converts the value to the standard unit with
  `Rescord.Units.convert/3`, and refuses a value outside the range with
  "is outside the range of Weight: 50 g to 80000 g". The range is given
  in the standard unit, as it is stored, not in the unit that the person
  typed. A unit that does not convert to the standard unit is not checked
  against the range. Outside the range is refused, not a warning
  (judgement call 5): a warning that a volunteer clicks past would still
  put the mistake in the chart.
- **A new standard unit** converts the range to it when the two units
  have the same dimension, and empties it otherwise, or when the kind has
  no standard unit any more (`Rescord.Lists.Changes.RangeFollowsStandardUnit`).
- **A measurement from before stays**, with its chart. A correction is
  checked only when it gives the value, the unit or the kind, as with the
  standard unit (ADR 0094).

### Consequences

- The tenant migration `20261128141450_add_measure_kind_ranges` adds two
  empty columns, and changes no row. No kind has a range until an
  administrator gives one.
- The message of the range is in the words of the validation, as the
  message of the unit is, because the error of a fact of an entry loses
  the values beside its message on the way out.

## A monthly share of Ruby for each member

### Context

The allowance of Ruby is for the whole organisation (`allowance` of
`Rescord.Ruby.Settings`, whole US cents for a month of UTC). Each member
is limited to 6 messages a minute and 120 a day, and a reply can take up
to 8 tool rounds. So one member, or a script with their session, could
use the allowance of the month in a few days, and then nobody else in the
organisation could ask Ruby until the next month.

### Decision

- **`member_allowance` of `Rescord.Ruby.Settings`**, whole US cents for a
  month, `min: 0`, `max: 10_000_000`, empty by default. Empty means no
  share: each member can use up to the allowance of the organisation, as
  before (judgement call 4). The share is the same for each member, not
  set member by member (judgement call 1), and members with the power
  `settings` have it too (judgement call 2).
- **`Rescord.Ruby.Allowance.member_room?/3`** sums the rows of
  `Rescord.Ruby.Usage` of one member in the month, which has `user_id`
  already, so no new table is needed. `room?/2` keeps its arity and checks
  the organisation; `say` asks the organisation first and the member
  second, so a month that is used for everybody says so.
- **A new reason of refusal**, `:member_allowance`, in
  `Rescord.Ruby.Reason`, which `Rescord.Ruby.refusal/1` gives, with its
  sentence in `RescordWeb.RubyWords`: "You have used your share of Ruby
  for this month. It starts again on 1 December 2026." The way on is the
  link to the settings, for a person who can change them.
- **The settings page** has the field "Share of one member for a month,
  in US dollars", and, with a share, a count of the members who have used
  it this month (`Rescord.Ruby.members_at_share/1`): a count, with no name
  and no cost of a person (judgement call 3). A table by member is a
  decision about what an administrator sees of a colleague.
- The run after a member confirms a proposal is never refused for the
  share, as it is never refused for the allowance: it calls neither.

### Consequences

- The tenant migration `20261128143308_add_ruby_member_allowance` adds
  one empty column, and changes no row. Nothing changes for an
  organisation until an administrator sets a share.
- As with the allowance, the check is before a reply and the price is
  known after it, so a member can end the month above their share by the
  replies that ran at that moment.
