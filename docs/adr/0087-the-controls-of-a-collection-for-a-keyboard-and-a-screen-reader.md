# ADR 0087: The controls of a collection, for a keyboard and a screen reader

Status: accepted. It does what ADR 0017 says the module can do, and it is
the next step that ADR 0084 names. The maintainer has not looked at it
yet.

## Context

ADR 0014 lists the gaps in the accessibility of the markup of Cinder, and
ADR 0017 closed the first: the sort of a table column. Two stayed: the
choice filter said nothing of its state, and the pages were not a `nav`.

ADR 0084 put the filters and the pages of Cinder on more pages, so more
people meet those gaps. The accessibility audit of 28 November 2026 looked
at the collections in a browser and found more:

- The button of a choice filter does not say that its list is open.
- A label names that button, so its name is "Sex" and the choice on it,
  "Female", is in no name.
- An arrow key in the list chooses the next choice, and the list closes
  under the focus, which then falls to the top of the page.
- The button that clears a filter holds "×", and that is its name.
- The drawings of Cinder are not hidden from a screen reader.
- A table has no name.
- Nothing says that a result changed after a filter or a search.

A stylesheet can close none of these, and the markup is in the
LiveComponent of Cinder, where we can put no hook.

## Decision

`assets/js/cinder_tables.ts`, the module of ADR 0017, closes each one in
the browser, in the same way.

- **A button that opens a list** (the choice filter, and the size of a
  page) gets `aria-controls`, and `aria-expanded` that follows the list.
  LiveView opens and closes the list in the browser, with no patch, so a
  `MutationObserver` follows it (`watch`).
- **The name of the button of a choice filter is its label and its
  choice**: "Sex: Female". Its list is a `radiogroup` with the name of the
  filter. The button of the sizes is "Show 25 per page", and its list is a
  `group`.
- **The keyboard in a choice filter:**
  - An arrow key moves through the choices, and the list stays open. The
    browser sends a click for the choice that an arrow key makes, and
    Cinder closes the list on a click. `holdOpen` stops a click that a key
    made (its `detail` is 0) before LiveView sees it. The change still
    goes to the server, so the rows follow each press, as they do for a
    `select` of the browser.
  - Enter and Escape close the list, and the focus goes to the button.
  - The list closes when the focus leaves it.
  - When the list closes under the focus, as after a choice with a mouse,
    the focus goes to the button.
- **The pages** are a navigation landmark with the name "Pages", and the
  page that shows has `aria-current="page"`.
- **A button with a sign for its text** ("×", a number, an arrow) gets the
  words of its `title` as its name. The button that clears one filter
  says which: "Clear filter: Sex".
- **Each drawing of Cinder** gets `aria-hidden`.
- **A table gets a name**: the heading of the section that it is in, or
  the heading of the page.
- **A collection says its state.** It has `aria-busy` while it loads. One
  status region of the page (`role="status"`), which the module adds to
  the `body`, outside the markup of LiveView, says what a collection shows
  after it changes: the line of the pages ("Page 2 of 3 (showing 26-50 of
  61)"), the words of its empty state, or "10 results". It says nothing
  for the first result of a page.
- `app.js` starts `watch` and `holdOpen` once. `enhance` runs after each
  patch, as before.
- `vendor.css` hides the status region from the eye.

## Consequences

- `RescordWeb.Features.CollectionsTest` holds this in a browser, on the
  list of the residents: `aria-expanded` follows the list; the name of
  the button follows the choice; the arrow keys move through the choices
  with the list open and the focus in it; Enter and Escape close it with
  the focus on the button; a choice with the mouse gives the focus to
  the button; the status region says the new count; and the marks
  survive a change of page.
- No test here reads the page as a screen reader does. Nobody has
  listened to these pages with VoiceOver, NVDA or TalkBack yet.
- `RescordWeb.CinderTest` holds each selector of the module to the markup
  of Cinder, and the calls in `app.js`. A release of Cinder that changes
  that markup fails the test.
- A click that a screen reader makes for a person can have no count of
  presses, as a click from a key. The list then stays open after such a
  choice, and Enter or Escape closes it.
- The words "Pages" and "results" are English, and those of Cinder come
  from its own translations. The pages of Rescord are in English
  (ADR 0075).
- The count of active filters of Cinder does not count the search. It
  stays so.
- The module depends on the markup of a dependency. Each of these is a
  change to give back to Cinder. When Cinder has one, take that part out
  of the module, with its test.
- Cinder can put the first page of a collection into the markup of the
  server (`initial_load: :sync`). We do not use it: a collection loads
  after the page opens, and shows the overlay of Cinder until then.
