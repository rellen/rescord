# ADR 0099: A link to a live page moves over the open socket

Status: accepted (the maintainer, 28 November 2026, chose "Yes, live
navigation for in-app links" to fix the double read). ADR 0096 measured
the double read, in its section on reads after the mount, and issue 20
holds the same numbers in a comment.

## Context

A LiveView mounts twice on a page that the browser loads as a document:
once for the HTTP response, and once when the socket connects. No page of
Rescord guards a read in `mount/3` with `connected?/1` or moves it to
`assign_async/3`, so each read of a page runs twice on such a load. On a
small test refuge (8 residents) that was 131 and 128 queries for the first
page of an organisation, 170 and 167 for a resident, 98 and 95 for the
tasks.

A move with live navigation (`<.link navigate>`, `push_navigate/2`) mounts
the new page once, over the socket that is open, and sends no document.
The links inside the pages mostly did that already. The site menu, the
list of the parts on the first page of an organisation, and a few other
links were plain `<a href>`: each press on one was a load of a document,
and paid the double read. No ADR chose plain links there.

## Decision

- **A link to a live page of Rescord is `<.link navigate={...}>`.** That
  holds for the site menu (each part of an organisation, and Root), the
  parts on the first page of an organisation, the dose calculator in the
  tools, the shared lists on the page Root, the assistant on the page
  Root, and the organisations of a person on the page Root.
- **A link to anything else stays `<a href>`:** a file (a PDF, a CSV, a
  photo, an attachment, a receipt), a page that a controller renders (the
  first page of Rescord, the colophon, the sign-in), and a page outside
  Rescord. Sign out stays a link with `method="delete"`.
- **A move between the two live sessions** (`:organisation` and `:root`
  in the router) is still a load of a document: LiveView does that by
  itself for a `navigate` to another session, and the link needs no other
  spelling. A `navigate` in the layout of a page that a controller
  renders also loads a document, as a plain link does.
- **The focus and the title need nothing new.** `assets/js/focus.ts`
  (ADR 0090) already gives the focus to the heading of a live page that
  took the place of another one, and LiveView sets the title of the
  document from `page_title`.
- **The first load of a tab and a reload still read twice.** There the
  HTML arrives with its content, which a person with no script, a slow
  socket or a screen reader is helped by. A read stays in `mount/3` until
  the metrics (ADR 0077) say that it is slow, as ADR 0096 says.

## Consequences

- A press on the menu sends no document and makes about half of the
  queries that it made.
- The popover of the menu is part of each page, so it is closed on the
  new page.
- A test that follows a menu link gets a live redirect:
  `render_click/1` then answers `{:error, {:live_redirect, %{to: path}}}`,
  and `follow_redirect/2` mounts the new page.
- The permission lookups (the member, its role and the organisation, read
  again for each read) are most of the queries that are left. Caching
  them for one request is a design of its own.
