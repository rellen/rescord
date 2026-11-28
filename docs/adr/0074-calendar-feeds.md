# ADR 0074: A member subscribes to a calendar feed

Status: accepted (the maintainer asked for calendar feeds on 28 November
2026, and left the design to judgement; the design is issue 3 of the
repository). It adds to ADR 0020, ADR 0024, ADR 0033, ADR 0040, ADR 0063
and ADR 0065.

## Context

A member reads the tasks of the day on the page of the tasks, and the
first page says what needs somebody now (ADR 0065). A person who is not at
Rescord sees neither. Most people already look at a calendar app each day,
and each calendar app can subscribe to a calendar at an address: a file of
iCalendar text (RFC 5545) that the app reads again on its own schedule.

Rescord already has what a calendar holds. A routine makes its tasks a
number of days ahead (ADR 0033), an absence has the day on which the
resident is expected back, and a lot has an expiry date.

A calendar app that changes a record of Rescord is a second thing: CalDAV,
or an account of Rescord at a calendar service, with credentials to keep.
This record is about the first thing only.

## Decision

### A feed

- **A member makes a calendar feed**: an address that their calendar app
  subscribes to. Rescord publishes, and the app reads. Nothing in a
  calendar app changes a record of Rescord: an event links to its record,
  and the page of the record does the work (ADR 0065).
- **A feed is a record**, `Rescord.Calendars.Feed`, in the schema of the
  organisation, in a domain of its own, `Rescord.Calendars`. A member
  chooses its parts when they make it:

  | Part | Source | Event |
  | --- | --- | --- |
  | Tasks | `Rescord.Tasks.calendar/2` | An event at the time that the task is due, 15 minutes long. The choice: the tasks that name me; those and the tasks for each member; each task; none. |
  | Expected back | `Rescord.Residents.calendar/1` | The day on which a resident that is away is expected back, as an event of the whole day. |
  | Expiry dates | `Rescord.Inventory.calendar/1` | The expiry date of a lot that has stock, as an event of the whole day. |

- **Each domain says what its dated things are**, with a function
  `calendar`, as each domain says what needs somebody (ADR 0065) and gives
  its grants (ADR 0024). `Rescord.Calendars.entries/4` asks each of them,
  and knows nothing of what an entry means.
- **A feed has a window and a limit.** It holds what is dated from 7 days
  before today, and each later thing that exists, 2,000 events at most,
  the nearest first. A task of a routine exists only as far ahead as the
  routine makes its tasks.
- **A member has 10 feeds at most.** Each feed is an address that reads
  the data of the organisation.

### The address is the key

- A calendar app cannot sign in. So the address holds a token, and a
  person who has the address reads the feed:
  `/o/<short name>/calendar.ics?token=<token>`.
- **The token is 32 random bytes, and Rescord stores only its SHA-256
  hash.** A copy of the database opens no feed. The page shows the
  address one time, when the feed is made. A person who loses it revokes
  the feed and makes another. A token has 256 random bits, so a plain
  hash is enough: nobody can try each token. The hash is not a secret
  that Rescord reads back, so it needs no vault (ADR 0068).
- **The token is a parameter named `token`**, which the log of the
  parameters of Phoenix leaves out, and the path of the request has none.
  A version of the paper trail holds neither the token nor its hash.
- **No `webcal` link.** The scheme `webcal` stands for HTTP, and an app
  may ask over HTTP first, which would send the token with no encryption.
  The page gives the `https` address in a field, with a button that
  copies it.
- **A feed belongs to one member, and reads as that member.** Each read
  for the content runs as the user of the member, with the organisation
  as the tenant, so the policies decide what the feed holds. No read for
  the content passes `authorize?: false`. Nobody is signed in when a
  calendar app asks, so the organisation, the feed and its member are
  found with no policy, by the token.
- **A feed reads while its owner could make it.** At each request,
  Rescord asks the policy of the action `subscribe` about the owner. So
  a feed stops when a person revokes it, when the member is removed, and
  when the role of the member loses the power. A removed member is
  archived, and a later invitation makes a new member: the feeds of the
  old one stay dead.
- **One answer for each refusal**: an organisation that is not there, a
  token of no feed, a feed that was revoked, and an owner who cannot have
  a feed now all get the same 404.
- **`revoke` empties the hash and archives the row.** The row and its
  history stay, and nothing reads the feed again.
- **A limit.** One client address gets 60 answers in a minute, counted
  with `Rescord.RateLimit` (ADR 0020), and then 429 with the time to wait.
- **Cheap to ask again.** The answer has an `ETag` that changes only with
  the content, and a request that names it in `If-None-Match` gets 304.
  The calendar says that an hour is a good time between two reads. A
  calendar app decides for itself, and some take many hours.
- Rescord writes when a calendar app last read a feed, once an hour at
  most. The paper trail does not record that mark.

### What an event holds

A feed leaves Rescord: a calendar service keeps a copy of it on servers
that the refuge does not run. So an event holds the least that is useful.

- An event has the title, the kind, the names of the residents, groups
  and locations that it is for, its state, and a link to the record in
  Rescord.
- **An event never holds the name or the address of a member.**
- **The words that a person wrote are in a feed only when the member
  ticks "Include the notes"**, which is off at first: the note of a task,
  the reason that a task was skipped, and the reason of an absence.
- **The state of a task is a word.** A task that is done starts with
  "Done:", and a skipped one with "Skipped:" and has the status
  `CANCELLED`. A calendar shows no shape and no colour of ours.
- **An instant is in UTC**, so a feed needs no `VTIMEZONE`. A day is a day
  of the organisation (ADR 0026).
- **A task is 15 minutes long.** A task is due at an instant, and a
  calendar draws an event with a length.
- **No reminder.** An event has no `VALARM`. Calendar apps often ignore the
  alarms of a calendar that they subscribe to, and a person sets an alert
  for the calendar in the app.
- `Rescord.Calendars.ICalendar` writes the text: the escapes, the fold of
  a line at 75 octets, `CRLF`. It is plain code, with no new dependency.
  The words and the links of an event are in the web layer,
  `RescordWeb.CalendarEvents`.

### Who can do what

- **A new power, `calendar`**: "Subscribe to a calendar feed". A feed
  copies data out of Rescord, so it is a power that an administrator can
  take from a role, and not a thing that each role can do.

  | Action | Grant |
  | --- | --- |
  | Make a feed (`subscribe`) | the power `calendar` |
  | Read and revoke a feed of one's own | the power `calendar`, with the scope `own` |
  | Read and revoke the feed of each member | the power `members` |

- **The migration gives the power to the two roles that each organisation
  starts with**: the administrator, as ADR 0040 says for each new power,
  and the member, because a feed is for the person who does the tasks. A
  role that an administrator defined gets it when an administrator ticks
  it.
- **A person with the power `members` sees who has a feed**, and when a
  calendar app last read it, and can revoke it. That person reads no
  address: Rescord stores none.
- **No action takes the owner as input.** `subscribe` reads the member of
  the actor. A root user who is not a member has no feed.
- No role has a grant for `mark`, which Rescord runs.

### The page

- `/o/<short name>/calendar` has the feeds of the person, the form of a
  new feed, the address of a feed that was made a moment ago, and how to
  subscribe in the common apps. It is built from function components
  (ADR 0037), for a phone first (ADR 0061).
- The button that copies the address is a small script,
  `assets/js/copy.ts`: a long address is hard to select with a finger.
  Without the script the field still works.
- The first page of an organisation and the page of the tasks lead to it.

## Consequences

- A member sees the work of the refuge beside the rest of their day, in
  an app that they already open.
- A calendar is late. An app reads a feed on its own schedule, and some
  take many hours. The page says so, and Rescord itself shows the tasks
  as they are.
- Data of the refuge is on the servers of a calendar service, for each
  member who subscribes with one. An administrator who does not want that
  takes the power from the roles. The notes stay out of a feed unless the
  member asks for them.
- **A person who has the address reads the feed, until somebody revokes
  it.** A reverse proxy that logs whole addresses holds the tokens in its
  log: `docs/self-hosting.md` says so.
- A task that is still due after 7 days leaves the calendar. The first
  page of the organisation still shows it (ADR 0065).
- A feed with more than 2,000 events leaves out the ones that are
  furthest ahead. They come into the feed as their time comes.
- The read of a feed costs the queries of its parts at each request that
  does not match the `ETag`: Rescord builds the calendar to know that it
  did not change. The limit of a client bounds it.
- A feed is not in the export (ADR 0054): it is a setting of one member.
- A new dated thing is a clause of the function `calendar` of its domain,
  a clause of `RescordWeb.CalendarEvents`, and a part of the feed.

## Not in this record

- A calendar app that writes back: to complete a task from a calendar,
  CalDAV, or a push to a calendar service. The credentials of such an
  integration are an Ash resource with its secret in the vault and a page
  for an administrator (ADR 0068), never a variable of the environment.
- A feed of the organisation with no member behind it, for a screen on a
  wall.
- A feed of one resident, and the dates of the journal: the last day of a
  prescription, the next vaccination.
- `VTODO` items, and reminders by email or by a chat service.
- A file for one task, to add it to a calendar one time.
- A view of a week or a month inside Rescord.

## Tests

- `Rescord.Calendars.ICalendarTest` holds the text: the escapes, the
  folds, `CRLF`, an instant and a day.
- `Rescord.CalendarsTest` holds the resource: the token that is shown one
  time and stored as a hash, the scope `own`, the power `members`, each
  way that a feed stops, and what the calendar of a feed holds.
- `RescordWeb.CalendarFeedControllerTest` holds the address: the words of
  the events, the `ETag`, the one answer for each refusal, the limit, and
  a log with no token.
- `RescordWeb.CalendarPagesTest` holds the page, and
  `RescordWeb.Features.PhoneTest` holds it on a phone.
- `Rescord.PolicySweepTest` holds each action of the feed (ADR 0063).
