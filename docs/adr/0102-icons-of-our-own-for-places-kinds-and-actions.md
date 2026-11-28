# ADR 0102: Icons of our own for the places, the kinds and the actions

Status: accepted. The maintainer asked for the design (issue 28, 28
November 2026) and chose to build all three phases on a decision card.
The four other calls of the issue (paw prints for the groups, a building
for the organisation, an icon on the heading of each place, the signs of
female and male) took the choice of the design: the maintainer did not
answer them.

## Context

ADR 0004 took out Heroicons, and `CoreComponents.icon/1` drew 13 icons of
our own. A survey of each page found two places where a person scans and
an icon helps most: the menu, a long list of the parts of the site, and
the kinds of a journal entry. It also found actions that come back on many
pages (add, change, remove, download, upload, undo, end), and a fault:
"Profile picture" was a state of the kind `info`, so it drew a clock,
which means "waiting".

## Decision

- **The icons are a module of their own**, `RescordWeb.Icons`, with
  `icon/1`. A drawing is the inside of the `<svg>`, kept in one map. The
  attribute `name` takes only a known name, so an unknown literal name
  still gives a compile warning.
- **The drawing.** A square of 24 units; the lines stay inside the square
  from 2 to 22; one line of 2 units with round ends and joins; no fill; a
  dot is a line of no length; the colour of the words; 1em. A name says
  the shape, not the meaning.
- **A meaning names its shape in one place**: `Icons.section/1` for a
  part of the site, `entry_kind/1`, `movement/1` and `sex/1`. The menu,
  the page of the organisation, the parts that need attention, the
  reports and the heading of a page read `section/1`, so one place has
  one shape everywhere.
- **Where an icon goes**: before the words of a link of the menu and of
  the page of the organisation, of the `h1` of a place (`header/1` takes
  `icon`), of the kind of a journal entry and of each event of the
  timeline, on the `summary` or the button of a common action, on the
  figures of the expenses, on the kind of each movement of the stock, and
  on a heading of a setting (money, time zone, language).
- **Where no icon goes**: the button that sends a form whose `summary`
  has the icon, each "Save", Cancel, a heading that says the `h1` again, a
  link inside a sentence, an option of a `select`, the head of a column,
  the name of a record (but in the list of who lives in a place, where a
  paw and two paws tell a resident from a group), a chart, a photo, the kinds of an arrival and of a
  departure.
- **An icon is never alone.** It is `aria-hidden`, and words beside it
  say what it means. No control shows an icon alone, but the close button
  of a notice, which has its `aria-label`.
- **One shape has one meaning.** The profile picture is a label with a
  star, not a state.
- **The chevrons of Cinder** keep their class names, which Cinder writes.
  `vendor.css` draws them with a CSS mask of our own chevrons, 1em big, in
  place of solid triangles. The span keeps the colour of its parent in
  forced colours (`forced-color-adjust: none` over `currentColor`).
- **Left for later**: a magnifying glass in the search field of Cinder
  and a funnel on its filters. Cinder draws both, and a picture there
  needs CSS on its markup that a new version of Cinder could break.

## Consequences

- A new icon is a line of the map in `RescordWeb.Icons` and a line of the
  example `icons.html.heex` of the catalogue. `CatalogueControllerTest`
  fails for an icon that is not there.
- A new part of the site gets a clause of `Icons.section/1`, and a new
  kind of journal entry a clause of `Icons.entry_kind/1`;
  `RescordWeb.IconsTest` fails for a kind with no shape.
- On a wide screen the links of the parts are closer than in the sheet
  of a phone, so the parts of the fixture of the tests, with a long name
  of the organisation, still fit one row at 1280 pixels
  (`PhoneTest`). A longer name, or a new part, can take a second row.
- The chevrons of Cinder are written twice, in `RescordWeb.Icons` and in
  `vendor.css`. `RescordWeb.IconsTest` holds the two equal.
