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
