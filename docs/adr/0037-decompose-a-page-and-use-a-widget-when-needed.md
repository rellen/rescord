# ADR 0037: Decompose a page, and use a widget only when it is needed

Status: accepted (chosen by the maintainer, 16 November 2026). It changes
ADR 0003.

## Context

ADR 0003 made each page a composition of live widgets. No page used a
widget: each LiveView held its state, its events and all of its markup, and
several grew past 400 lines. The maintainer answered: "Only use widgets when
we need them, but we should aggressively decompose live views in to
function components, live widgets or nested live views".

## Decision

- **A LiveView decomposes its page.** It keeps the route, the state, the
  events and the layout. Its `render/1` composes parts, and a part is in a
  module of its own.
- **A part is a function component by default.** A section of a page, a
  table, a form, a row and a list of words are each a function component,
  in a module of components for its area:
  `lib/rescord_web/components/<area>_components.ex`, for example
  `RescordWeb.InventoryComponents`. A component takes what it shows as
  attributes, declared with `attr`, and reads no socket.
- **A part becomes a live widget only when it needs state of its own**
  that the page does not need: a part that two pages share with its
  events, or a page with several instances of one stateful part. ADR 0003
  still says how to build one.
- **A part becomes a nested LiveView only when it needs a process of its
  own**, as `docs/architecture.md` says.
- A LiveView that grows past about 250 lines is a sign that a part is still
  inside it.

## Consequences

- The events stay in the LiveView, so one module answers each event of a
  page, and its tests do not change.
- A component that another page needs is in one place already.
- `RescordWeb.Widget` and the `:widget` setup stay, for the first widget.
