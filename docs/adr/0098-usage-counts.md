# ADR 0098: Usage counts, kept on the server unless its operator sends them

Status: accepted. The maintainer asked on 28 November 2026 for telemetry
that shows which features are in use, with two conditions: an
installation can send it nowhere, and where it goes is the choice of the
person who runs it. Issue 23 is the design. In the quiz of the same day
the maintainer asked for OpenTelemetry for the send ("Why not open
telemetry? Everything should be what Ash, Ash metrics, and other
libraries already use, right?"), and confirmed that sending is opt-in.
The other calls of section 9 of the issue stand.

## Context

ADR 0077 gave the operator a log and a metrics endpoint. They describe
the health of the server, not which features people use. The people who
build Rescord want to know that too, and have no view into a server that
they do not run.

What Hex had on 28 November 2026, read in the sources:

- `opentelemetry` 1.7.0 is stable for traces only. Metrics are in
  `opentelemetry_experimental` 0.6.0, "unstable signals".
- `opentelemetry_ash` 0.1.4, and the packages for Phoenix, Ecto and Oban,
  make spans, not metrics.
- The bridges from `Telemetry.Metrics` to OTLP are
  `otel_metric_exporter` 0.4.4 ("unofficial", with protobuf, finch and
  retry) and `otel_telemetry_metrics` 0.1.5 ("temporary library").
- The SDK sets `service.instance.id` to the node name, which holds the
  host name or an address, adds attributes of the process, is set from
  application env and `OTEL_*` variables (which ADR 0068 rules out for a
  setting), and pushes every few seconds, which says when people work.

## Decision

1. **Count on `:telemetry`.** The counts come from the events that Ash
   and Phoenix emit already: the actions of Ash
   (`Rescord.Usage.Actions`), the connected mount of a LiveView and the
   dispatch of a file route (`RescordWeb.Usage`). A count is a day in
   UTC, a feature of a fixed list (`Rescord.Usage.Features`), a kind
   (`page`, `action`, `file`), the name of the item as the code names it,
   and a number. It holds nothing of a person, an organisation, a record
   or a host. Only the outer action of a process counts, and only one
   whose actor is a user, so a job does not. Tests fail for a page, a
   domain, a resource or a file route with no feature and no reason.
2. **Memory, then the database.** `Rescord.Usage.count/3` adds one in a
   public ETS table, and emits `[:rescord, :usage, :count]`. Each minute
   `Rescord.Usage.Counter` writes the table as upserts that add, to
   `Rescord.Usage.Count` (shared schema, no history), so several nodes
   can count for one server. The counts are kept 400 days.
3. **Three modes, the default `local`.** One row of
   `Rescord.Usage.Settings` (ADR 0068: an Ash resource, the token under
   AshCloak, no environment variable): `off` counts nothing, `local`
   keeps the counts on the server for its root users, `send` also sends
   each full day to the one address that a root user named. Rescord has
   no address of its own in the code. A root user sets it at
   `/root/usage`, which shows the exact bytes of a send first.
4. **OTLP as the export, written by Rescord.** The default format is an
   OTLP `ExportMetricsServiceRequest` in its JSON form, built by
   `Rescord.Usage.Document`: one metric `rescord.usage.count`, a
   monotonic sum with the temporality delta, a point for each count of
   the day, and a resource with `service.name`, `service.version` and a
   random `service.instance.id` that a root user can make new. Any OTLP
   endpoint takes it at `/v1/metrics`. The plain JSON document of issue
   23 is the second format. A send is one `POST` with `Req`, with no
   redirect and no retry; the hourly job `Rescord.Usage.Workers.Send`
   sends each full day not sent yet, from the day that sending was
   turned on, 7 days back at most, and none with no count. A token goes
   only to `https://` or to this machine.
5. **The metrics endpoint too.** In each mode but `off`, the counter
   `rescord_usage_count` with the labels `feature` and `kind` is on the
   endpoint of ADR 0077. An operator whose collector pulls needs no
   address in Rescord.
6. **No new dependency.**

## Consequences

- A server that upgrades counts on the server and sends nothing. The
  upgrade notes say so, and how to turn the counts off.
- A day with one person on a server still says what that person used.
  So nothing leaves until the operator decides, and the page says why.
- An action counts when it ran, also when it refused its input: the
  event of Ash does not say how it ended. A bulk action of Ash has no
  actor in its event, so it does not count.
- When a stable OpenTelemetry package for metrics exists, the document
  can move to it if it can be held to the same fields. That is a new
  decision of the maintainer.
- The counter of the metrics endpoint is in memory, and starts at zero
  when Rescord starts. The day counts in the database are the record.
