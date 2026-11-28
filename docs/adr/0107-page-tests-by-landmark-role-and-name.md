# ADR 0107: Page tests on PhoenixTest, by landmark, role and name

Status: accepted (the maintainer, 28 November 2026: "we need to use his
library now and also lean into landmarks and semantic HTML"). Issue 33
holds the design and the spike.

## Context

The pages are semantic and classless (ADR 0004) and keep WCAG 2.2 AA
(ADR 0090): each page has one banner, one `main`, one footer and one `h1`,
each section has a name from its heading, each field has a label, and each
repeated button has a name of its own. The tests used little of it: 59% of
about 945 selectors started with a DOM id, a button was pressed by its
event, and a change of markup that a person would not notice broke tests
(the icons of ADR 0102 in the headings). Two assertions could never fail:
`html =~ ~s(role="alert")` finds the hidden alert of the layout.

PhoenixTest, which the browser tests use already, finds fields by label
and buttons by words. Alone it is not enough: `click_button/2` matches a
part of the words and prefers them to `aria-label`, so it finds each
"Done" of a list, and `within/3` takes CSS only.

## Decision

- **A page test uses PhoenixTest**, in a LiveView test, a controller test of
  an HTML page and a browser test. A response that is no page stays on
  `Phoenix.ConnTest`, and a component test on `render_component/2`.
- **`RescordWeb.Roles` (`test/support/roles.ex`) finds what a person finds.**
  `use RescordWeb.Roles` (in a browser test, `browser: true`) imports
  PhoenixTest with `within/3`, `assert_has/2,3`, `refute_has/2,3` and
  `click/2` of the module, which take a locator or a CSS selector.
  Locators: `main`, `banner`, `contentinfo`, `navigation`, `region`,
  `complementary`, `article`, `heading`, `button`, `link`, `field`,
  `table`, `row`, `form`, `list` (by its label), `item`, `figure`,
  `image`, `details` (by the label or the words of its summary),
  `definition` (the `dd` of a term), `alert`, `status`, narrowed with a
  pipe. Queries: `has?`, `all`, `one`, `text`, `names`, `href`, `src`,
  `attribute` and `value`. `assert_has/3` takes `state:`, the kind of a
  `data-state` that the element holds, with its words in `text:`.
- **The name is a short form of the W3C computation**: `aria-labelledby`,
  `aria-label`, the label of a field, the caption of a table, the words of
  a button, a link, a heading or a row. What is `aria-hidden` is left out,
  and what is `hidden` is not found. In a browser test the locator becomes
  a selector by role of Playwright, which computes the name itself.
- **One means one.** A locator that `click/2`, `within/3` or `one/2` finds
  none or several times raises, with its description.
- **An id, a `data-` attribute or a raw event stays where it is what the
  test holds**: an id of an address or of `focus.ts`, records that only an
  id tells apart, the controls of Cinder, `data-state` and `data-label`,
  the state of the connection, and an event that the page does not offer.
- **`PhoenixTest.Driver.render_html/1` has no documentation**, and the
  module reads the page with it, so `phoenix_test` stays at `~> 0.14.0`
  and an update runs `RescordWeb.RolesTest`.
- **The tests move area by area**, each area in one commit on `main`.

## Consequences

- A test reads as the page reads: `click(region("Lots") |> button("Take off
  B-1"))`. A name that changes on the page fails the test, as it would
  confuse a person who uses a screen reader.
- Names that `cinder_tables.ts` gives in the browser (the name of a table,
  the "Pages" navigation, the buttons of a filter) are only in browser
  tests.
- `assert_has/3` of PhoenixTest.Playwright puts its selector in `css=`, so
  an assertion by role runs inside `within/3` on `:scope`.
- A change of a Cinder filter does not reach the path of a PhoenixTest
  session; a test of the address opens the page at the address.
