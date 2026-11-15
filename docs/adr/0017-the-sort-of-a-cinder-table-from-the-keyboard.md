# ADR 0017: We work around the sort of a Cinder table for the keyboard

Status: accepted (chosen by the maintainer, 15 November 2026)

## Context

ADR 0014 lists the gaps in the accessibility of the markup of Cinder. The
first is the sort of a table column: a `div` with a click, which takes no
focus from the keyboard, in a header cell with no `aria-sort` and no
`scope`. A person who uses a keyboard cannot sort a table.

There were two ways: give the change back to Cinder and wait for a release,
or work around the gap here. The maintainer chose the second.

A stylesheet cannot close this gap. Cinder renders the table inside its own
LiveComponent, so we cannot put a hook on its elements either.

## Decision

- `assets/js/cinder_tables.ts` changes the table in the browser:
  - the sort control gets `role="button"` and takes the focus, and Enter or
    Space presses it;
  - the header cell gets `scope="col"`, and `aria-sort` while its column is
    sorted. It reads the direction from the class of the icon of Cinder.
- `assets/js/app.js` calls the module through two callbacks of LiveView:
  - `onBeforeElUpdated` marks the element that a patch is about to put in the
    page. Without it the patch takes the attributes off, and the control
    loses the focus each time the table loads again. A browser showed that.
  - `onPatchEnd` marks a table that is new on the page.
- The module is TypeScript, as each piece of code for the browser is.
- `vendor.css` gives the control the look of a button that is as wide as its
  words, so the focus ring is around them.

## Consequences

- A browser showed the result on the day of this record: the Tab key reaches
  the control, Enter and Space sort, the focus stays, and `aria-sort`
  follows the sort and survives a change of page. No test in the repository
  runs a browser.
- `RescordWeb.CinderTest` holds what the module reads to the markup of
  Cinder: the two selectors, and the class of the icon for each direction.
  It also holds the two callbacks in `app.js`. A release of Cinder that
  changes that markup fails the test.
- The other gaps of ADR 0014 stay: the choice filter has no `aria-expanded`
  and no role for its list, and the pages are not a `nav` with
  `aria-current`. The same module can close them in the same way.
- The module depends on the markup of a dependency. When Cinder closes the
  gap itself, remove the module, its rule in `vendor.css`, and its tests.
- esbuild removes the types and checks none. A type check needs `tsc`, which
  is not set up (`docs/architecture.md`, "Code in the browser").
