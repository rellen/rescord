# ADR 0061: Rescord is mobile first

Status: accepted (the maintainer asked for it on 27 November 2026: "we
really should be mobile first"). It changes the type scale of ADR 0015, and
it adds to ADR 0004 and ADR 0014.

## Context

A member of a refuge uses Rescord beside the animals, with a phone in one
hand. The pages were written and looked at on a wide screen. An assessment
of each page at the width of a phone found the problems that
`docs/mobile.md` lists. The largest were these:

- the site menu took five lines at the top of each page of a phone, and
  wrapped on a wide screen for a person with a long address;
- each table was wider than the phone, and its last columns, with the
  buttons, were out of view;
- a button, a field, a summary and a link of a menu were lower than a
  finger needs;
- the text of a control was 15px, and Safari on a phone makes the page
  larger when such a control gets the focus.

## Decision

- **The phone is the first screen.** A rule of the stylesheet with no media
  query is the rule of a phone. A query adds what a wider screen has room
  for. A query for a narrow screen (`width < 40rem`) is right only where
  the wide rule is what the browser does anyway, such as the layout of a
  table. A new page is looked at with a width of 360px and of 320px before
  a wide screen, in the light and in the dark scheme.
- **Nothing scrolls sideways.** No page is wider than a screen of 320px
  (WCAG 1.4.10), and no part of a page scrolls sideways in a box of its
  own.
- **What a finger presses is 44px high or more** (WCAG 2.5.5). The token
  `--tap` holds the size. A button, a field, a select, a summary, the label
  of a box and a link of a menu are that high on each screen: a wide screen
  can have a touch screen too. A link in a line of words is not that high.
  A link that is the title of a row or of a card takes a larger area to
  press than its words, with a pseudo-element.
- **The text of a control is 16px.** The body is 16px on a phone and 15px
  from 48rem. This changes the body of 15px of ADR 0015 for the phone.
- **The site menu is a popover on a phone.** The bar holds the name of the
  site and the button Menu, and stays at the top of the screen. The button
  opens the menu with the `popovertarget` attribute: the browser opens it,
  and closes it on a press outside it and on the Escape key. There is no
  script. A browser with no popover shows the menu in the page. From 60rem
  the menu is in the page, in two rows: the name of the site and the
  account, then the parts of the organisation. Two rows hold a long name
  and a long address. The link of the part that the page is in has
  `aria-current`: a page says its part with the `section` attribute of
  `Layouts.app`.
- **A table is a list of cards on a phone.** Below 40rem each row is a
  card. Its first cell is its title. Each other cell says its column with
  `data-label`, on the cell, or on an element inside the cell where Cinder
  writes the cell. The header row stays in the page for a screen reader,
  out of view. The sort controls of a table of Cinder are in its header, so
  that header stays in view as a line of sort controls. The table stays a
  `<table>`: Chromium, Gecko and WebKit keep its meaning for a screen
  reader when CSS changes its `display`.
- **A form is one column, and its button is as wide as the form** on a
  phone. A control of the type `number` gets an `inputmode`, so a phone
  shows its keyboard of digits.
- **A hover is inside `@media (hover: hover)`.** After a touch a hover
  stays on the element, and says nothing.
- **A flash message is at the foot of the screen on a phone**, where it
  does not cover the bar and its menu.
- `RescordWeb.Features.PhoneTest` holds the rules in a browser with the
  screen of a phone: no page is wider than the screen, the menu opens and
  closes, a table is a list of cards, and each control is high enough.

## Consequences

- A button and a field are a little higher on a wide screen than before.
  The site bar has two rows on a wide screen in an organisation.
- A new table gives each cell but the first a `data-label`. A cell with no
  label still reads, with no name of its column on a phone.
- A new page passes `section` to `Layouts.app`, or the menu marks no part.
- A person who reads the page with Safari before version 17, or Firefox
  before version 125, has no popover: the menu is in the page, below the
  bar, and each link works.
- The assessment used Chromium with the screen of a phone. Nobody looked at
  the pages with Safari on a phone. What to look at there is in
  `docs/mobile.md`.
