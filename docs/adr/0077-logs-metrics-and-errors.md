# ADR 0077: Logs, metrics and errors: what Rescord uses, and what it adds

Status: accepted. The maintainer asked on 28 November 2026: "Are we using
AshMetrics? Are we logging best practice? Are we using Splode?" This
record builds the log (L1 to L6), the endpoint of the metrics (M1) and
the errors (E1, E2 and E4). Each of L7 and M1 needs a new dependency, so
the maintainer chose on the same day: the endpoint of the metrics, and
not JSON. L7 stays a proposal. E3 was built later the same day, after
the locale of an organisation (ADR 0075).

## Context

Nobody had looked at how Rescord says what it does: its log, its metrics,
and the shape of its own errors. No record covers them. A rescue runs
Rescord on a server of its own, and the person who runs that server has
the log and nothing else when a thing goes wrong.

This record read the code of `main`, and the source of each package at
the version of `platform/mix.lock`, or of Hex for a package that Rescord
does not have:

| Package | Locked | Newest on Hex | In Rescord |
| --- | --- | --- | --- |
| `telemetry` | 1.4.3 | 1.4.3 | Phoenix, Ecto, Oban and Ash emit events through it |
| `telemetry_metrics` | 1.2.0 | 1.2.0 | the list of the generator, read by no reporter in a release |
| `telemetry_poller` | 1.3.0 | 1.3.0 | started, with no measurement of our own |
| `splode` | 0.3.3 | 0.3.3 | through Ash only |
| `ash_metrics` | not a dependency | 0.6.0 (5 October 2026) | not used |
| `logger_json` | not a dependency | 7.0.4 | not used |
| `peep` | not a dependency | 6.0.0 (12 November 2026) | not used. This record adds it (M1) |
| `prom_ex` | not a dependency | 1.12.0 | not used |
| `opentelemetry`, `opentelemetry_ash` | not dependencies | 1.7.0, 0.1.4 | not used |

## The answer in short

| Question | Answer | What to do |
| --- | --- | --- |
| Do we use AshMetrics? | No. Rescord had the metrics list of the Phoenix generator, and no reporter read it outside development. | Not AshMetrics now (M2). First an endpoint that a collector can read (M1), which this record builds. |
| Do we log well? | In part. What Rescord writes itself is careful. What its libraries write is not: a page that crashes writes what the person typed, and a job that fails writes nothing. | L1 to L6, which this record builds. JSON waits (L7). |
| Do we use Splode? | Only because the errors of Ash are Splode errors. Rescord defines none. | No second tree of errors (E1). A new failure of our own is a Splode error in a class of Ash (E2). A safe line for the log reads the tree (E4). |

## What the code had before this record

**Metrics.** `RescordWeb.Telemetry` is the module that `mix phx.new`
writes: summaries of Phoenix, of the queries of the repo, and of the VM.
`Telemetry.Metrics` only describes a metric. A reporter must read the
list, and Rescord starts none. The router gives the list to LiveDashboard,
and mounts LiveDashboard only when `dev_routes` is set, which is
development. So a release measures nothing that a person can read. No
metric names an Ash action, a job, an email or a photo.

**The log.** The formatter is the plain one of Elixir, with the time, the
level and one field: `request_id`. A release writes at `info`, and no
setting changes that. Seven places in `lib/` call `Logger`. Each one is
careful: it writes an id, a count or the name of a module, and
`Rescord.Accounts` says why it never writes the message of an error.
`:filter_parameters` holds `password` and `token`. `AGENTS.md` says never
to log a token, a link, a private key or the text of a conversation.

**Errors.** `splode` is in `mix.lock` because Ash needs it. No module of
Rescord says `use Splode.Error` or `defexception`. A function of a domain
fails in one of three shapes: an error of Ash, an atom
(`{:error, :busy}`, `{:error, :not_found}`), or a sentence
(`{:error, "The date is after today."}`). `Rescord.Accounts.error_messages/1`
reads the classes of Ash and makes the words of a page, and 6 pages and a
controller have a clause of their own for a sentence.

## What we tested

Each line is a result that we saw, with PostgreSQL 18, on `main` of 28
November 2026.

1. **A page that crashes writes what the person typed.** A LiveView whose
   `handle_event/3` raises is a GenServer that stops, and Elixir writes the
   last message of such a process. The line held
   `"value" => "note=TYPED-SECRET+medical+note"`: the fields of the form.
   `:filter_parameters` does not reach it, and the level `info` does not
   stop it.
2. **A page that crashes on a message writes the message.** With a record
   in the message, the line held each field of the record. The message that
   a widget reloads on holds a record.
3. **A job that fails writes nothing.** Two jobs failed in a queue, one
   with a raise and one with `{:error, ...}`, and the log was empty. Oban
   records the error in the row of the job, and writes a line only when a
   logger is attached. Rescord attaches none.
4. **The logger of Oban writes the arguments of the job.**
   `Oban.Telemetry.attach_default_logger/1` puts `args` in each line. The
   job that sends the email of an invitation (ADR 0067) holds the address
   of the person in its arguments. So that logger is not the answer.
5. **The message of an Ash error holds the value.**
   `Exception.message/1` of an invalid attribute gave
   `Value: "VALUE-SECRET@example.org"`. Two lines of Rescord log such a
   message today (`Rescord.Tasks.generate/2` and the job of the routines),
   and the export shows one on a page.
6. **Ash takes a Splode error of our own.** A module with
   `use Splode.Error, fields: [:what], class: :invalid` became an entry of
   `Ash.Error.Invalid`, and `error_messages/1` gave its words with no
   change. The same failure as a sentence became `Ash.Error.Unknown`: Ash
   then reads a fault of a person as a fault of the code.

## Decision

### The log

**L1. Each line says whose it is.** The fields of a line are
`request_id`, `user`, `organisation`, `job`, `worker`, `queue` and
`attempt`. A request and a page set the id of the user and the id of the
organisation. A job sets its own fields, and the organisation when the job
has a tenant. `Rescord.Log.context/1` sets them. An id is not a name: the
log holds no email address and no name of a person.

**L2. A job that fails writes a line.** A handler of our own listens to
the events of Oban. A failure that Oban tries again is a warning, and the
last failure is an error. The line holds the id of the job, the worker,
the try, and the safe reason of L4. It never holds the arguments.

**L3. A crash report holds no message of a process.** A translator of our
own (`Rescord.Log.Translator`) stands in front of the one of Elixir. It
replaces the last message of a process that stops, the queue of a state
machine and the arguments of a task with their shape: `{:record, map(2)}`,
`%Phoenix.Socket.Message{}`. The exception and the stack trace stay, and
they name the function and the line.

**L4. A line never holds the message of an error.** `Rescord.Log.reason/1`
gives the safe text of any failure: the class and the modules of a Splode
error with the fields that are atoms
(`invalid: Ash.Error.Changes.Required(field: :name)`), the module of each
other exception, an atom as it is, and the shape of the rest. A test reads
the code of `lib/` and fails for a call of `Logger` that uses `inspect` or
a function of `Exception`.

**L5. The operator sets the level.** `RESCORD_LOG_LEVEL` is `debug`,
`info`, `warning` or `error`, and `info` is the default. It describes the
process, so it is in the environment by test 3 of ADR 0068. At `debug`
the libraries write the parameters of each query and of each event of a
page, and the state of a process that stops. The guide says to use it for
a short time, and to treat that log as the data of the rescue.

**L6. The levels have one meaning each.** `error`: Rescord lost work, or
needs the operator. `warning`: a thing failed, and Rescord goes on or
tries again. `info`: what an operator wants to see on a normal day.
`debug`: for a person who looks for a fault.

**L7. JSON, when the operator asks (proposed, not built).**
`RESCORD_LOG_FORMAT=json` would write each line as one JSON object, with
the fields of L1 as keys, for a server that sends its log to a collector.
The default stays text, which a person reads in `journalctl` and
`docker compose logs`. The formatter would be `logger_json` 7.0.4, which
is a new dependency. The maintainer did not take it on 28 November 2026:
no server sends its log to a collector yet. We do not write a formatter
of our own: a crash report, a binary that is no text and a struct are
each a case that the package already handles.

### What stays out of the log

No line that Rescord writes holds: the name or the address of a person,
text that a person typed, a token, a link or a key, the bytes or the name
of a file, the message of an error, or the arguments of a job.

Two limits remain, and the guide for an operator states them:

- A crash report holds the message of its exception. An exception of a
  library can name a value.
- A path holds the short name of an organisation and the id of a record.

So the log of a server is as private as its database.

### Metrics

**M1. An endpoint for a collector.** When the operator sets
`RESCORD_METRICS_PORT`, Rescord answers `GET /metrics` in the format of
Prometheus on that port, and 404 for each other path there. The port is
not the port of the pages, so a reverse proxy does not publish it, and it
listens on the address of `RESCORD_LISTEN_ADDRESS`. It has no sign-in.
Test 3 of ADR 0068 puts the port in the environment. With no port,
Rescord starts no reporter and measures nothing.

- **The list** is `RescordWeb.Telemetry.metrics/0`, which replaces that
  of the generator: the requests by status and by route, the pages by
  module, the queries and the wait for a connection, the actions of Ash
  by domain, kind, resource and action, the jobs of Oban by worker, queue
  and result, the emails by result, the photos that waited too long for a
  slot of libvips, and the memory, the run queue and the processes of the
  VM. Each name starts with `rescord`, and each time is in milliseconds,
  in 14 buckets from 1 ms to 30 s.
- **A tag holds nothing that a client sends**: no id, no name, no path of
  a request, no HTTP method, and not the name of an event of a page. A
  client can send any text there, and each new text is a new series, so
  such a tag lets a client fill the memory. A tag is a route pattern, a
  module, an atom or a status.
- **One event for each action.** Ash emits an event for each kind of
  action of each domain (`[:ash, :residents, :create, :stop]`), and only
  while something listens. `Rescord.Metrics.attach/0` listens to them and
  emits `[:rescord, :action, :stop]`, so that one metric covers them. It
  listens only when the port is set, or in development for LiveDashboard.
- **The reporter is `peep` 6.0.0.** It reads the `Telemetry.Metrics`
  list, it needs three small packages that Rescord already has, and its
  last release is of this month. It has no summary, so each time is a
  distribution. The maintainer chose it on 28 November 2026.

A host that scrapes Prometheus and draws the graphs then shows a server
with no more work than the port.

**M2. Not AshMetrics now.** The package is real, and its idea fits Ash: a
`metrics` block on a resource that becomes `Telemetry.Metrics`
definitions. We do not add it today, for four reasons:

- Its README says "Experimental", and that the DSL can change in a minor
  release. It had seven releases from 18 September to 5 October 2026 and
  none since, from one maintainer who is not of the Ash team.
- It makes definitions for a reporter to read. Rescord has had one only
  since M1, so no person has asked yet for a count that it lacks.
- A gauge of a resource of an organisation runs its queries one time for
  each organisation in each period, because each organisation has a schema
  (ADR 0011).
- A number about the work of a rescue (the residents in care, the tasks
  that are overdue) belongs on a page of that rescue, read from the
  database with the grants of the person. ADR 0065 does that. A metric is
  for the operator of the server.

Look again when a person wants a count that no event of a library gives,
such as the transfers or the tokens that the assistant uses, and when the
package has a release that it calls stable. Until then such a count is
one `:telemetry.execute/3` and one line of `Rescord.Metrics`, as the
photos have.

**M3. No traces now.** OpenTelemetry needs a collector, and no server of
Rescord has one. `opentelemetry_ash` exists for the day that one does.

**M4. LiveDashboard stays in development.** It shows the state of each
process, and so the data of each organisation, also to a root user who
may not read them (ADR 0069 keeps a conversation from a root user). A
release does not mount it.

### Errors

**E1. No second tree of errors.** Rescord does not make a Splode root of
its own (`use Splode, error_classes: [...]`). Each action already answers
with the classes of Ash: `forbidden`, `invalid`, `framework`, `unknown`.
A second tree would need a change of shape at each call.

**E2. A new failure of our own that can reach a person is a Splode error
in a class of Ash.** It is a module with
`use Splode.Error, fields: [...], class: :invalid` (or `:forbidden`), in
the domain that returns it. It is not a sentence. Test 6 shows that Ash
and `error_messages/1` take it as it is. The fields say what failed, so a
page can say it in the language of the person, and the assistant can say
why a draft was refused. A sentence from a change becomes
`Ash.Error.Unknown`, which says "a fault of the code" to each tool that
reads the class.

An atom stays right for a result that the caller matches and that no
person sees: `{:error, :busy}`, `{:error, :not_found}`, the reasons of
`Rescord.Transfers.Crypto`.

**E3. The sentences of the domain became errors of E2 (built).** Each
place of the domain that returned a sentence now returns one of six
errors, each with a reason that is an atom and never a value that a
person typed:

| Error | Class | Reasons | Returned by |
|---|---|---|---|
| `Rescord.Accounts.Errors.InvalidTime` | invalid | `:after_now`, `:not_a_time` | `Accounts.instant/2`, `Accounts.local_instant/2` |
| `Rescord.Export.Errors.InvalidDate` | invalid | `:after_today`, `:not_a_date` | `Export.export/3` |
| `Rescord.Export.Errors.Unreadable` | unknown | the name of the file | `Export.export/3` |
| `Rescord.Storage.Errors.RefusedFile` | invalid | `:empty`, `:too_large`, `:not_a_photo_or_pdf`, `:not_a_photo`, `:busy`, `:unreadable`, `:too_many_pixels` | `Storage.Upload.prepare/1`, `Images.prepare/1` |
| `Rescord.Tasks.Errors.NoPrescription` | invalid | | the change that writes a dose |
| `Rescord.Accounts.Errors.InvitationNotSent` | unknown | | the action that sends an invitation |

A change of a resource that stores a file puts its field on a
`RefusedFile` (`:content`) and adds that error to the changeset, so the
action answers `Ash.Error.Invalid` with it inside.
`Rescord.Accounts.error_messages/1` takes one error of Rescord as well as
an error of an action. For an error of Rescord it gives the words of the
module, after the name of the field when it has one, and with no bread
crumbs of Ash in front. The words of the pages did not change, except
that the dose now starts with a capital. The pages of a resident, a
group, the measurements, the tasks and the journal lost their clause for
a sentence; the page of a location keeps one for its own words; the
export controller says the words of the error.

What stays a sentence, on purpose: the words that a page or a controller
writes itself for its own form ("Choose a resident or a group", "The date
is not a date." of the reports), the casts of the types of the units,
which follow the rule of Ash for a type, the changes of the expenses that
add an error with a field and a message, which Ash already classes as
invalid, and the answers of the tools of Ruby, which are words for the
model. A second language for the pages, when it comes, translates the
words of each module from its reason.

**E4. The log reads the tree.** `Rescord.Log.reason/1` (L4) walks the
classes of a Splode error. This is the use of Splode that Rescord has
from today.

### A place to see the errors

Rescord sends its errors to no service. An operator finds them in the
log, as lines with the level `error`. A tracker that keeps the errors in
the database of Rescord itself (`error_tracker`), or an outside service,
is a later choice. An outside service is an integration, and so a
resource (ADR 0068).

## Consequences

- A person who runs a server can follow one request, one user, one
  organisation or one job through the log with `grep`.
- A job that fails is in the log, with the worker and the try. Before,
  only the table of the jobs said so.
- A crash of a page no longer puts a form, a record or a photo in the
  log. A crash report says less: the shape of the last message, and not
  the message. The stack trace still names the line.
- `RESCORD_LOG_LEVEL` and `RESCORD_METRICS_PORT` are two more names in
  the environment, both by test 3 of ADR 0068, and both optional.
- A server with the port set has one more listener, with no sign-in. The
  guide says to keep it inside the network of the server.
- `peep` is one more dependency.
- A new `Logger` call that uses `inspect` fails a test. The value goes
  through `Rescord.Log`.
- `Rescord.Log.shape/1` and `Rescord.Log.reason/1` are not about Rescord.
  They are candidates for `shoddy`.

## Options that this record sets aside

- **The logger of Oban.** It writes the arguments of each job (test 4).
- **A smaller limit of `:translator_inspect_opts`.** It shortens a last
  message. A short message still starts with what the person typed.
- **No crash reports of processes at all.** They are how a fault of a
  page is found.
- **PromEx for M1.** It brings dashboards for Grafana and plugins of its
  own for Phoenix, Ecto and Oban. It has no plugin for Ash. A
  `Telemetry.Metrics` list, which is what Rescord has and what AshMetrics
  makes, goes into it only through a plugin that we would write.
- **`telemetry_metrics_prometheus_core` for M1.** It reads the same list
  as `peep`. Its last release is of March 2024.
- **Business numbers as metrics.** See M2: they are pages.
