# ADR 0090: The accessibility audit, and the test that holds each page to it

Status: accepted. The maintainer chose the test dependency `a11y_audit`
(28 November 2026). The maintainer has not looked at the rest yet.

## Context

Rescord says that its markup is semantic and that each page is accessible
(ADR 0004, ADR 0015, ADR 0061). Until now a person read the markup, and
`RescordWeb.TokensTest` held the contrast of the colours. Nothing asked a
browser.

On 28 November 2026 an audit ran axe-core 4.14 in a real Chromium against
40 kinds of page and 2 states, at 320, 360 and 1280 pixels, in the light
and in the dark scheme: 249 audits. The rules were those of WCAG 2.0, 2.1
and 2.2 at the levels A and AA, and the best practices of axe-core. A
script also read the landmarks, the headings and the titles, and a person
followed the focus of the keyboard through the main flows.

38 of the 40 pages broke no rule of axe-core. The landmarks, the one
`h1`, the order of the headings, the labels, the contrast, the size of
what a finger presses and the text alternatives of the charts were right.
The audit still found these:

1. **The page of an error was bare.** `Not Found` with no `html lang`, no
   title, no landmark, no heading and no stylesheet.
2. **A receipt that is a file was a link with no name**, and the button
   beside it had the name "Take invoice.pdf off" under the words "Take
   off". A person who speaks to the device says the words that show, and
   the name did not start with them (WCAG 2.5.3). More buttons had a name
   of this kind.
3. **The pages with no session all had the title "Rescord".** A page with
   no title of its own would have the title "Rescord · Rescord".
4. **The focus fell to the top of the page** after a press on a button
   that the next render does not have (Done of a task), and after a link
   to another live page, which also announced nothing.
5. **A choice filter of Cinder** said nothing of its state, lost its
   choice from its name, and closed under the focus. ADR 0087 closed
   these, in the thread of the collections.
6. **No page had a footer landmark**, and nothing said which version of
   Rescord a person was using or where its source is.
7. **The loading bar moved** for a person who asks for less motion. It
   was the script topbar, which draws on a canvas and does not read the
   setting.
8. **A report is a tagged PDF** (a language, a title, headings, header
   cells with a scope), but it does not state that it conforms to PDF/UA.
   Typst 0.15 through AshTypst 0.6.1 offers PDF 1.7, A-2b and A-3b only.

## Decision

### What the audit found

- **An error page is a page of Rescord.** `render_errors` names the root
  layout, and `RescordWeb.ErrorHTML` renders `Layouts.plain`: the skip
  link, the site header, `main` with one `h1`, and the site footer. The
  words say what happened and what to do: "Rescord has no page at this
  address" for 404, "Something went wrong" for a 5xx. The page shows no
  detail of the error.
- **Each page has a title of its own, and the name of the site after
  it**: "Residents · Rescord". The root layout writes it, and
  `Layouts.title/1` gives the words of the error to an error page. A
  controller passes `page_title` as a LiveView assigns it.
- **The name of a control starts with the words that show on it.** "Take
  off" has the name "Take off invoice.pdf", and "Pause" of a routine has
  "Pause the routine Clean the shed". An `aria-label` adds what the
  control acts on, after the words.
- **A link that shows a picture or a file type has a name**: the name of
  the file and its kind.
- **The site footer** (`Layouts.site_footer/1`) is a `footer` with a
  `nav` named "About Rescord": the colophon, the accessibility statement
  and the source code. A member also reads the version there. A page
  with no session does not show the version, so that it tells a stranger
  nothing about the server.
- **The colophon** is a public page at `/colophon`: what Rescord is, its
  licence, what it is built with, how the pages are made, and the
  accessibility statement, which says what is tested and what is not
  right yet. It names no instance and no person.
- **The loading bar is CSS.** `app.js` sets `data-loading` on the root
  element while LiveView loads, and `layout.css` draws the bar. The base
  layer already stops each animation for a person who asks for less
  motion. `assets/vendor/topbar.js` is gone.

### The focus of the keyboard

`assets/js/focus.ts` keeps the focus in its place when LiveView changes
the page.

- It notes the element that has the focus, and the parts of the page
  around it.
- After a patch, when that element is gone and nothing has the focus, the
  focus goes to the element with the same `id`, or to the first control
  of the nearest part that is still there. A part that LiveView put in
  again is found by its `id`, so the focus stays in the row of the
  button.
- Most pages load themselves again after an action, with `push_navigate`
  to their own address. The module treats that as the same page and puts
  the focus back in the same way.
- A live page that takes the place of another one gets the focus on its
  `h1`, which a screen reader then reads.
- The module never moves a focus that the page still has.

So a row, a card and a list item that hold a button need an `id` that
stays the same from one render to the next. The streams have one. The
Cinder rows have none: ADR 0111 finds them by their `data-item-id`.

### The test

`RescordWeb.Features.AccessibilityTest` holds each kind of page to the
rules, in the browser of the browser tests (ADR 0023).

- It runs axe-core with the same rules as the audit, on a phone and on a
  wide screen, in the light and in the dark scheme, on each page with no
  session and each page of `RescordWeb.PagesFixtures`.
- It runs our own checks, which axe-core does not ask: one `main`, one
  site header, one site footer, the skip link as the first stop of the
  Tab key, one `h1`, no level of heading skipped, a name of its own for
  each `nav`, a language, and a title that ends with the name of the
  site.
- It holds four states: a form with its errors, the open menu, an open
  filter of a list, and a notice.
- With the text spacing of WCAG 1.4.12, no page is wider than 320 pixels.
- The focus stays in the row after Done of a task, and goes to the
  heading of a new live page.

The Hex package `a11y_audit` (MIT, test only) carries the script of
axe-core and turns its result into a message that names the rule, the
element and the fix. The release has no new dependency.

`RescordWeb.PagesFixtures` makes the refuge that `PhoneTest` made before,
and names its pages. `PhoneTest` and `AccessibilityTest` both use it, so
a new page is added in one place and gets both.

## Consequences

- A page that breaks a rule of axe-core now fails CI, with the name of the
  page, the rule and the element.
- axe-core finds a part of the problems of a page: Deque, which writes
  it, counts 57 of each 100 problems that its own audits found. No test
  reads a page as a screen reader does. Nobody has used Rescord with
  VoiceOver, NVDA or TalkBack yet, and the accessibility statement says
  so.
- The tests use Chromium only. Safari and Firefox are not checked
  (ADR 0061 says the same).
- A table that we write has no `caption`. Each one is in a section with a
  heading, and the tables of Cinder get the heading as their name
  (ADR 0087). axe-core does not ask for a caption. This stays.
- A point of a chart answers a pointer and not the keyboard. The table
  below the chart has each value. This stays.
- A report does not claim PDF/UA. When Typst and AshTypst offer it, turn
  it on in `priv/typst/look.typ` and say so in the colophon.
- The focus module depends on events of LiveView (`phx:page-loading-start`
  and `phx:page-loading-stop`, with their `kind`). A release of LiveView
  that changes them fails the two focus tests.
- The test takes about four minutes of the browser tests. It creates an
  organisation, so it does not run beside others.
- The colophon is a claim that a reader can check. Change it when the
  list of what is not right changes.
