# ADR 0106: Comments on records, and notifications on the page, on devices and on ntfy

Status: accepted (the maintainer, 28 November 2026). Issue 29 holds the
design, its mockups and the judgement calls; the maintainer answered each
of them, as the section "What the maintainer chose" says.

## Context

The members of a refuge talk about a resident, a task, an expense or a
transfer somewhere else: a chat group, a note on the fridge, a call. What
they say is not with the record, and a person who was not in the chat
does not hear it. The maintainer asked for comments on the records, with
a way to tell a member, and for notifications that reach a person on the
page, on their phone and on ntfy. No chat rooms.

A phone shows a notification on its lock screen, and a push service or a
server of ntfy holds it on the way. The records of a refuge are about
residents, and about people: a comment may name a person who surrendered a
resident, or a vet bill. So nothing of the record leaves the server.

## Decision

### Comments

- **A comment is on exactly one record**: a resident, a task, an expense,
  a transfer or a journal entry (`Rescord.Comments.Subject`). The table
  has a column for each, and a check holds that exactly one has a value.
  The comments of an entry are on the journal page of the entry alone
  (`?entry=<id>`), which each entry links to. A comment on a
  transfer is in the schema of the organisation that wrote it.
- **A person writes and reads a comment only on a record that they can
  read** through its own domain: a member who reads only their own
  expenses (ADR 0082) reads no comment on the expense of another member.
- **Two powers**: `comments` (write, and change or delete one's own) and
  `moderate_comments` (delete any). The data migration gives both to the
  role Administrator and `comments` to the role Member of each
  organisation; another role gets them on the page of the roles.
- **The words are a Markdown subset**, at most 4,000 characters: bold,
  italics, lists and links. `RescordWeb.Markdown` reads the text with
  MDEx and writes the HTML itself, from a list of the nodes that it knows;
  anything else is its words, escaped. No raw HTML. A link is a link only
  when its scheme is `https`, `http` or `mailto`, and it gets
  `rel="nofollow noreferrer"`.
- **Only the writer changes a comment**, and the page says that it was
  changed. The writer or a moderator deletes one, for real.
- **The history keeps no word**: the paper trail of a comment redacts the
  body, in its changes and in the inputs of the action. A version says who
  did what, when. It has no foreign key to the comment
  (`reference_source? false`), so a delete is a delete.
- **A member who left keeps their name on their comments**, marked
  "(former member)" (`Rescord.Comments.people/2`). A user that is gone
  shows as "a former member". Erasure on request is its own design: a
  moderator already deletes each comment of one person with
  `Rescord.Comments.erase/2`, and no page offers it yet.

### Telling and following

- **"Tell someone"** on the form: check boxes of the members, who get a
  notification of the kind `:told`. Display names and `@mentions` come
  later, with a design of their own.
- **The writer and each person told follow the record** from then on, and
  each follower gets a notification of the kind `:comment` for a new
  comment. The writer gets none for their own. A button on the record starts and stops a follow.
- **A notification is made by a job**: the action of a comment sends the
  signal `:commented` (`Rescord.Comments.Signals`), and
  `Rescord.Notifications.Notification` listens with AshOban, at most five
  tries. A person who is no member now, or who cannot read the comment as
  themselves, gets none.

### Notifications

- **The page of notifications** (`/o/:org/notifications`) lists them with
  the record, the sentence of the kind and the comment, and the bell in
  the site bar counts the unread ones. Opening the record marks its
  notifications as read. A job deletes them each night: 30 days after a
  person read one, 90 days after it was made.
- **A channel is a module** of `Rescord.Notifications.Channel`. There are
  two: Web Push and ntfy. A person chooses, for each kind, which channels
  get it ("What goes where"), from the channels that the server has on. The page of notifications always gets each one.
- **What a channel sends is a pointer** (`Rescord.Notifications.Message`):
  the name of the organisation, one sentence of the kind, and the address
  of the page of notifications. No record, no person, no word of a
  comment.

### Web Push and the installable app

- **The app can be installed**: `priv/static/manifest.webmanifest` with
  its icons, and a service worker, `assets/js/sw.ts`, which esbuild
  builds to `priv/static/sw.js` (the profile `rescord_worker`, which is
  not in git). The worker shows a notification and opens its page on a
  press. It has no handler of `fetch`: Rescord does not work offline.
- **The server encrypts and signs each message itself**, with `:crypto`
  (RFC 8291 and RFC 8292, `Rescord.Notifications.WebPush`), and sends it
  with Req. No library of Web Push.
- **The keys are made on the page of a root user** (`/root/push`), with
  the contact for the push services. They are kept in
  `Rescord.Notifications.Settings`, the private key encrypted with
  AshCloak, and no page shows it. No setting is in the environment
  (ADR 0068). New keys end each subscription.
- **A subscription is sent to only the push services of the browsers**:
  Google, Mozilla, Apple and Microsoft, over HTTPS on port 443
  (`WebPush.allowed_endpoint?/1`). A browser does not make the server
  call a host of its choice. A push service that answers 404 or 410 ends
  the subscription.
- **Safari on an iPhone gets notifications only from the app on the Home
  Screen**: the page says so, and how.

### ntfy

- **The server of ntfy and its access token are on the same page of a
  root user.** The token is encrypted with AshCloak, and goes from its
  form to the action and nowhere else.
- **Each person gets a topic of their own**, with a random name that
  nobody can guess, and can renew or stop it. The page shows the address
  to subscribe to. A topic is open to anybody who knows its name, so it
  gets the pointer and nothing more.

## What the maintainer chose

- Comments go on journal entries too, as a fifth kind of record (call 1,
  changed).
- Comments are a Markdown subset, rendered safely on the server, not plain
  text (call 6, changed).
- "Tell someone" now, and display names and `@mentions` later (call 2:
  "Both").
- The writer and the people told follow, with a button to stop (call 3).
- A notification on a device names only the organisation and its kind
  (call 4).
- The allow-list of push services stays (call 5).
- ntfy after Web Push, and no other channel for now.
- The history redacts the words of a comment, and a member who left keeps
  their name on their comments.
- A writer changes a comment at any time, and it shows "changed" (call 7).
- Notifications go 30 days after a person read them, and after 90 days
  at most (call 8).
- The power `comments` for the roles Member and Administrator, and
  `moderate_comments` for Administrator only (call 9).
- The comments are in the export, and the follows, the notifications and
  the devices are not (call 10).
- A task gets a page of its own (call 11).

## Consequences

- Three migrations, each with an upgrade note in `CHANGELOG.md`: the
  shared tables of the settings, the subscriptions and the topics; the
  tables of the comments and the notifications in each organisation; and
  the powers of the two roles.
- An operator who wants notifications on devices makes the keys and turns
  them on at `/root/push`. Nothing is sent until then, and the page of
  notifications works without it.
- The title of a task in a list is now a link to its own page,
  `/o/:org/tasks/:id`, which has its comments.
- The export of an organisation (ADR 0050) has the comments. It leaves
  out the follows, the notifications, the preferences, the subscriptions,
  the topics and the settings: they belong to a person or to the server.
- A mention by name, a comment on another kind of record, a digest by
  mail, and erasure on request are each a design of their own.
