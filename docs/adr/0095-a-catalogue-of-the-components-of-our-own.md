# ADR 0095: A catalogue of the components, of our own

Status: accepted. The maintainer chose a catalogue of our own over
Phoenix Storybook on a decision card (28 November 2026, issue 25).

## Context

Rescord has more than twenty modules of function components, and a
classless stylesheet that gives each HTML element its look (ADR 0004).
The only way to see a state of a component was to make the record that
brings it out. Some states are hard to reach: each kind of notice, each
error of a field, a button that is off.

The known tool for this is Phoenix Storybook (`phoenix_storybook` 1.5,
MIT). Issue 25 compares the two ways. What Phoenix Storybook costs here:

- Its own pages are Tailwind, and it loads the stylesheet of the
  application into the same document. It expects that stylesheet to keep
  to a sandbox class. Ours styles `button`, `header`, `nav` and `table`
  everywhere, so it would restyle the storybook. The way out is an iframe
  for each story, which its documentation names as the last resort.
- It wants a stylesheet and a script of its own beside `app.css` and
  `app.js`, so a second bundle.
- It is a dependency, with `makeup_eex` and `makeup_html`, and it is
  built with LiveComponents.
- Its playground changes the attributes of a component. Most of our
  components take records, and few attributes.

## Decision

Rescord has a catalogue of its own: one page at `/dev/components`.

- **The page is for a developer.** The router has it with the setting
  `catalogue`, which `config/dev.exs` and `config/test.exs` turn on. The
  release has no such page. It reads no database and shows no record.
- **An example is a template of its own**, in
  `lib/rescord_web/controllers/catalogue_html/examples/`, and a line of
  the list in `RescordWeb.CatalogueHTML` with its group and its title.
  The page renders the template and shows the text of the file below it,
  so the markup is written one time, the formatter formats it, and there
  is no macro.
- **The first step has three groups**: the elements that the stylesheet
  styles (text, lists, a card, a table by hand, `details`, a group of
  choices), each function of `CoreComponents` in each state, and the
  charts. The components of an area, such as the card of a resident, come
  later, with structs that the page builds in memory.
- **The page is a page of Rescord.** It uses `Layouts.app`, so an example
  shows in the real page, in the scheme of the device.
- **The tests visit it.** The page is in `RescordWeb.PagesFixtures`, so
  `PhoneTest` holds each example to a screen of 320 pixels and to the
  size of a finger, and `AccessibilityTest` holds it to axe-core in both
  schemes (ADR 0061, ADR 0090). A state that no fixture reaches is tested
  there.
- `RescordWeb.CatalogueControllerTest` fails for a public function of
  `CoreComponents` with no example, for an icon that the page does not
  show, and for a template that the list does not name.

## Consequences

- No new dependency, no second bundle and no class.
- The catalogue has no playground, no search and no page for each
  component. When one page is too long, a group gets a page of its own.
- An example keeps the rules of a page: its headings start at `h4`, each
  `id` starts with `example-`, and a `nav` has a name of its own. The
  header of a page (`<.header>`) has no example, because a page has one
  `h1`: the header of the catalogue is the example.
- The two modules of the catalogue are in the release, and no route
  reaches them there, as for the preview of the emails (ADR 0070).
- A new core component, or a new state of one, gets an example. A
  component of an area gets one when its group is added.
