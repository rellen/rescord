# ADR 0031: A details element keeps its state when the page is drawn again

Status: accepted

## Context

A page keeps a form that a person does not always need in a `<details>`,
which is closed at first. A person opens it, and the browser sets its
`open` attribute. The server does not know that.

When LiveView draws the page again, the new render has no `open`, and the
element closes. That happens while a person fills in the form: when the
form of a journal entry draws the fields of a kind, and when a page says
what is wrong. A page test does not see it, because it reads the markup and
not what a person sees. A browser test found it.

## Decision

- `keepDetailsOpen` of `shoddy_phoenix` keeps a `<details>` open: it runs
  before LiveView updates each element, and carries the open state to the
  new render. Until 28 November 2026 it was `assets/js/details.ts`.
- **Each `<details>` of a page has an id.** LiveView finds the same element
  in the new page by its id. Without one, a paragraph that comes above it,
  such as the words of a refusal, makes a new element of it, and it closes.
  `RescordWeb.DetailsTest` holds the rule.
- `RescordWeb.Features.JournalTest` holds both in a browser: it fails
  without the module.

## Consequences

- A `<details>` that a page must close after an action cannot rely on the
  next render. The pages open again after a write (ADR 0025), which gives
  each one its first state.
- This is a helper that is not about Rescord, so it went to
  `shoddy_phoenix` (its PR 35, 28 November 2026). `assets/js/app.js` imports
  it from `deps`, as it imports LiveView.
