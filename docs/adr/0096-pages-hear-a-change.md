# ADR 0096: Pages hear a change, and where streams and reads after the mount fit

Status: accepted (the maintainer asked on 28 November 2026: "Are we using
Ash notifications and pubsub to allow views to update live? Are we using
async assigns, streaming etc?"). The three decisions are built: each
resource has a notifier, and the first pages listen. The two parts on
streams and on reads after the mount are an assessment, and change no
code. The design is issue 20. This ADR carries out a sentence of
`docs/architecture.md` that no code followed, which ADR 0062 and ADR 0065
both noted. It adds to ADR 0009 (what the core publishes through), to
ADR 0065 (the first page) and to ADR 0014 (a collection of Cinder).

## Context: what Rescord did before

This ADR read each resource and each page at the commit before it.

- **No resource had a notifier.** No `pub_sub` section, and no
  `notifiers:`. `Rescord.PubSub` ran, and nothing published to it.
- **No page subscribed to anything.** Each of the 36 LiveViews ends with a
  `handle_info/2` that ignores each message. There is no live widget
  (`lib/rescord_web/widgets/` does not exist), so the rule of AGENTS.md "a
  widget reloads on the notification of its resource" had no user.
- **One page read again by itself:** the first page of an organisation,
  each minute, with a timer (ADR 0065). On each other page a change of
  another member showed after a reload.
- **Reads after the mount:** `start_async` in one place, the button that
  tries a provider of the assistant. No `assign_async`. The collections of
  Cinder read after the mount, because Cinder does (5 collections).
- **Streams of LiveView:** none. `<.table>` of `CoreComponents` takes one,
  and no page gives it one. A list is an assign, and the page reads the
  whole list again after each of its own actions.
- **No `:for` had a `:key`.**

So two members who worked on the same list of tasks did not see each
other, a transfer that arrived showed on no open page, and a person who
waited for a decision on an expense had to load the page again.

## Decision 1: each resource says that a record changed

`Rescord.Resource` gives each resource with a table the notifier
`Ash.Notifier.PubSub`, and its `pub_sub` section:

```elixir
pub_sub do
  module Rescord.Changes
  prefix "changes"
  transform &Rescord.Changes.change/1

  publish_all :create, [:_tenant, "tasks"]
  publish_all :update, [:_tenant, "tasks"]
  publish_all :destroy, [:_tenant, "tasks"]
end
```

A resource writes nothing for it. The last part of a topic is the domain
of the resource (`Rescord.Changes.key/1`).

- **`Rescord.Changes` is the module that the notifier calls** (ADR 0009:
  the core cannot name the endpoint). It is in the core, and it wraps
  `Phoenix.PubSub`. The web layer calls it for the topics.
- **A topic is one domain of one organisation.** A resource in the schema
  of an organisation has the topic `changes:org_<id>:<domain>`, from its
  tenant. A process subscribes with its own organisation, so it never
  hears another one. Each organisation has its own schema (ADR 0011), and
  now its own topics too.
- **A resource that organisations share has no tenant**, so `Rescord.Resource`
  gives it the notifier and no publication. Such a resource writes its own
  publications, with the attribute that holds the id of the organisation:
  a transfer and a partnership publish to both of their refuges
  (`[[:from_organisation_id, :to_organisation_id], "transfers"]`), a
  partner on another server to its refuge, an organisation to itself. Their
  topic is `changes:<id>:<domain>`. `Rescord.Changes.topics/2` gives both
  spellings, and a listener subscribes to both.
- **Some shared resources tell no page:** users, tokens, the keys of a
  refuge, the providers of the assistant and the base lists. No page of
  one organisation waits for one. `Rescord.ChangesTest` names them, so a
  new shared resource must choose.
- **A version resource has no notifier.** A page hears of the record.

## Decision 2: a change says that something changed, and not what

The message is a `Rescord.Changes.Change`: the domain, the resource, the
name and the type of the action, and the primary key. **It holds no
attribute of the record.**

This is what keeps a broadcast inside the policies. A notification of Ash
holds the whole record and the changeset. A topic is not a policy: each
process that subscribes gets each message, whatever its person can read.
A page that drew a record from a message would show a journal entry to a
member whose role cannot read the journal. So no record leaves the
process that wrote it:

- the `transform` of each resource is `Rescord.Changes.change/1`, which
  `Rescord.Resource` sets;
- `Rescord.Changes.broadcast/3` takes a `Change` and nothing else, so a
  publication with a `transform` of its own raises in the process that
  wrote, in the first test that runs the action;
- `Rescord.ChangesTest` sweeps each resource of each domain, as the sweep
  of the policies does (ADR 0063): the notifier, the module, the
  transform, no transform of a publication, and a publication for each
  kind of action.

**A process that hears a change reads again**, as its own actor, through
the code interface of the domain. The policies answer that read as they
answer each read. A change tells a person nothing but "read again", and
it goes to no browser.

What a change does tell a process: that a record of that domain changed
in its organisation. A page subscribes only for the domains that it
shows, and it shows nothing of a change but what its read returns.

## Decision 3: a page listens with `RescordWeb.LiveChanges.listen/3`

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> LiveChanges.listen([Tasks], &assign_tasks/1)
   |> assign(page_title: "Tasks")}
end
```

- It subscribes with `ShoddyPhoenix.LiveView.Subscriptions`, for a
  connected socket only, and attaches a `:handle_info` hook. The page
  keeps its `handle_info/2` that ignores the rest.
- **One read for many changes.** One action writes several records (a task
  and its subjects), and a job writes many (the tasks of the routines).
  The first change starts a wait of 250 milliseconds. The changes that
  come in that time start nothing more. Then the page calls its function
  once. A change that comes after that read began starts the next wait, so
  the last change is never missed.
- **The function reads and assigns, and leaves the forms alone.** A form
  that is not assigned again is not drawn again, so a person who types
  keeps the text. The page of the transfers had one function for its
  lists and its form: it is two now.
- **The process that wrote does not hear its own change.**
  `Rescord.Changes.broadcast/3` runs in the process of the action and
  leaves that process out. A page that writes reads again in its own
  event, as before, and does not read a second time. A job, a controller
  and a task of `start_async` are other processes, so the page hears them.
- **A change needs a commit, and Ash must know of the transaction.** An
  action inside `Rescord.Repo.transaction/1` loses its notification. Use
  `Ash.transact/3`, which sends them after the commit.
  `Rescord.Locations.move_location/3` changed for this. The tests set
  `config :ash, :missed_notifications, :raise`, so a test fails for an
  action that loses one.
- **In the tests the wait is 0.** The page reads in the message of the
  change, so a test writes and then renders. `with_slow_changes/1` of
  `RescordWeb.ConnCase` opens a page that waits, for a test of two presses
  in the same moment. `render_changes/1` of the same module renders a
  page with a collection of Cinder: the collection reads in a message
  that comes after the change.

### With Cinder

A page does not hold the rows of a `Cinder.collection`. Its function calls
`Cinder.refresh_table(socket, "<id>", silent: true)`, which reads with the
filters, the sort and the page that the person chose, and keeps the rows
on the page while it reads. The page of the expenses does this, and reads
its three sums itself. So ADR 0014 and this ADR fit: Cinder owns the rows
and how to read them, and `LiveChanges` says when.

**A collection of a temporal resource needs a new query, and not only a
refresh.** A query of a temporal resource holds the instant at which it
was built (`as_of`, ADR 0012), and a page builds the query of a
collection when it draws the collection. `Cinder.refresh_table` reads
that query again, so it reads the past: a test showed that an item that
another member adds is not in the list of the items after a refresh. An
expense and a task are not temporal, so their collections read the
present. For a temporal collection, the page must hold the instant of
its last read in an assign, give it to the query as `as_of`, and set it
again in its function: Cinder reads again by itself when the query
changes. The residents, the inventory and the history of an item are
such collections. None of them listens yet.

### With signals

A signal (ADR 0067) and a notification are for two things, and neither
does the work of the other.

| | A signal | A notification |
| --- | --- | --- |
| When | In the transaction of the action, or in a job | After the commit |
| Who hears | Another resource, which writes | A page, which reads |
| A fault in the one who hears | Undoes the action (inline) | Changes nothing |

A listener of a signal writes with an action, and that action has its
notification as each action has. So a page of the tasks hears that the
removal of a resident took a subject off a task. No page listens for a
signal, and no notifier writes a record.

### With the clock of the first page

The first page keeps its read of each minute (ADR 0065). The time alone
makes a task overdue, and no write says so. The page now also reads when a
record of one of its parts changes: `Rescord.Attention.domains/0` names
the domains that `parts/2` reads.

## The pages that listen now

| Page | Hears | Why it is first |
| --- | --- | --- |
| The first page | Tasks, inventory, residents, locations, transfers | It says what needs somebody now. A minute is long for that. |
| Tasks | Tasks | Several members work one list. "Take" is there so that two people do not do one task, and it works only when the other person sees it. |
| Transfers | Transfers | The other refuge writes, and nobody of this refuge does. |
| Partner refuges | Transfers | The same. |
| Expenses | Expenses | A person waits for a decision of another. It is also the first collection of Cinder that listens. |

## The pages that should listen next

Each is a call of `listen/3` and a function that the page mostly has.
They wait for work that changes the same pages now (issue 14 moves lists
to Cinder), not for a decision.

| Page | Note |
| --- | --- |
| An expense | The decision, the receipts and the history. |
| The journal of a resident, the conditions | After the journal is a collection of Cinder (M2 of ADR 0079). The page has several forms: read the entries, leave the forms. |
| The inventory, an item | The items and the history of an item are collections of Cinder of temporal resources (ADR 0088, ADR 0084): see "With Cinder" for what they need first. The page of an item has several forms. |
| The residents, a resident, the housing, a group | The list of the residents is a collection of Cinder of a temporal resource too: see "With Cinder". |
| The photos of a resident | A photo that another person adds. Low value. |
| The members and the roles | A page holds the role of its person from the mount. The policies still decide each action, so this is a button that is there and refuses, and not a hole. A page could read the role again when `Rescord.Accounts` changes. |

Not these:

- **The assistant (Ruby).** The chat has its own topic, of one
  conversation, and its own events with the text of a reply as it comes
  (ADR 0069). A `Change` says "read again", which is the wrong tool for a
  reply that grows each second. The messages publish as each resource
  does, and no page listens for the domain `Rescord.Ruby`: a page that
  did would read again each second while a reply comes.
- **A count in the site menu** (ADR 0065 left it for a notifier). Each
  open page would then read what needs attention at each change of five
  domains. It needs a cheaper read first.
- **Who else looks at a record** (`Phoenix.Presence`), and a warning in a
  form that the record changed since the person opened it. Both are
  possible on these topics. Nobody asked.

## Assessment: streams of LiveView

**Not now, with one exception that is designed already.**

A stream keeps the rows out of the memory of the server and sends only
the rows that changed. It costs: the page cannot read its rows any more
(the page of the tasks finds a task in its assigns before it acts on it),
and a filter or a sort means a reset of the stream.

- The lists of Rescord are short (the tasks of a day, the items of an
  organisation), or they are or become a collection of Cinder, which
  holds one page of rows and owns them. A stream and Cinder do not go
  together.
- LiveView sends only the rows that changed of a list in an assign too,
  when the `:for` has a `:key`. No `:for` had one. **A list that reads
  again after a change gives its rows a `:key`**: the table of the tasks
  does now.
- The long lists by hand are the timeline and the journal of a resident
  ("each entry, each time", ADR 0079). The answer for them is pages (M2 of
  ADR 0079), and not a stream of each entry.
- **The exception is the chat of the assistant**, whose messages only
  grow: ADR 0069 and its design make them a stream. That stays.

## Assessment: reads after the mount (`assign_async`, `start_async`)

**No `assign_async` now. A rule, the candidates, and two findings that
come before it.**

A LiveView mounts two times when the browser loads a page: for the HTTP
response, and again when the socket connects. Each of the 36 LiveViews
reads in `mount/3`, with no `connected?/1` and no `assign_async`, so
**each read of a page that the browser loads runs two times.** Measured
on the refuge of the report tests (8 residents), as queries of the HTTP
response and of the socket:

| Page | HTTP response | Socket |
| --- | --- | --- |
| The first page | 131 | 128 |
| A resident | 170 | 167 |
| The journal of a resident | 132 | 129 |
| The tasks | 98 | 95 |
| The inventory | 36 | 33 |

A move with live navigation (`<.link navigate>`, `push_navigate`) mounts
one time, on the socket that is open. So the double read is the price of
a page that the browser loads, and two findings say how often that is and
how much it costs:

- **The site menu is plain links.** Each of its entries, and the list of
  the parts on the first page, is an `<a href>`. A press there loads the
  page, and reads two times. The links inside the pages are mostly
  `navigate` links (99 of them). No ADR chose plain links for the menu.
  With live navigation there, only the first page of a tab and a reload
  read two times, and for those the content in the HTTP response is worth
  its read.
- **Most of the queries are one lookup, many times.** Of the 131 queries
  of the first page, 41 read the member, 40 read the role and 13 read the
  organisation: the check of the grants looks them up for each read. To
  look them up once for a request takes off about 70 of 100 queries of
  that page, in both renders. It changes the checks of the policies, so it
  gets a design of its own.

`assign_async` reads one time, after the socket connects, and the page
shows before the read ends. It costs a state of "reading" on the page
that a screen reader must hear, a face for a read that failed, and an
HTTP response with no content in that part. It comes after the two
findings above, for the reads that are still slow then.

- **A read that the page is for stays in `mount/3`**, until a number says
  that it is slow. The metrics endpoint has the time of each mount and of
  each event, by LiveView (ADR 0077). Nobody has looked at those numbers
  on an instance with real records, and this ADR did not guess them.
- **Make a slow read fast before making it late.** The page of the
  inventory read each stock movement of the organisation. ADR 0088 made
  the level a calculation, which helps each reader, and not only the
  first paint.
- **Candidates for `assign_async`**, in the order of what the code
  suggests: what needs attention on the first page (five domains; the
  links to the parts would show at once), the choices of the form of a
  new task (four reads for a form inside a closed `<details>`), the
  timeline, and the charts of the measurements.
- **Candidates for `start_async`**: an event that works outside the
  database while the page waits and can show nothing. The photos that a
  person sends (the page makes the sizes in its own process), the import
  of a transfer file, and the receipts of an expense. The button that
  tries a provider does this already.
- A PDF and a CSV file are plain requests to a controller, so a page does
  not wait for them.

## Consequences

- A member sees what another member, a job or another refuge did, in about
  a quarter of a second, on five pages. Each other page is as before.
- A resource publishes with no line of its own. A new shared resource
  fails `Rescord.ChangesTest` until it publishes or is on the list of the
  quiet ones.
- Each write sends one small message for each resource that it changes.
  With no listener it goes nowhere.
- A page that listens reads again for each change of its domains in its
  organisation, and not only for the records that it shows. A `Change`
  has the resource and the key, so a page can look before it reads, when
  a read is dear. No page does yet.
- A row that a person has the focus in can go away under them, when
  another person finishes the task of that row. The page has no button
  for a task that is done, so the person cannot press it; the focus goes
  to the document. This is what the minute read of the first page did
  already.
- On one machine `Phoenix.PubSub` is local, and `docs/self-hosting.md`
  describes one machine. On several machines the nodes must form a
  cluster (Rescord starts `DNSCluster` when `DNS_CLUSTER_QUERY` is set).
  An instance with several machines and no cluster shows a change only to
  the pages on the machine that wrote. Nothing breaks: the other pages
  are as they were before this ADR.
- No migration, no setting and no new dependency.
- `docs/architecture.md` and AGENTS.md now say what the code does.
