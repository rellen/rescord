# ADR 0014: Cinder shows each collection

Status: accepted (asked for by the maintainer, 15 November 2026)

## Context

Most pages of Rescord show a collection of records: the residents, the tasks
of a day, the lots of an inventory. Each needs filters, a sort, a search and
pages. Cinder (0.18.1) builds all of that from an Ash query, as a table, a
list or a grid, and reads the filters from the attributes of the resource.

Cinder does not fit three rules of this project as it comes:

- It renders through a LiveComponent of its own. ADR 0003 has no
  LiveComponent.
- Its markup has Tailwind classes. Each built-in theme is a set of them, and
  about 40 more are written into the markup itself. ADR 0004 has no class and
  no Tailwind.
- `mix igniter.install cinder` sets Tailwind up.

We tried it before we decided, in a copy of the application:

- A temporal resource in the schema of an organisation shows through Cinder.
  The query carries the tenant and `as_of`, and the result is the rows of
  that instant.
- The web layer passes a query that the code interface of a domain builds
  (`query_to_<name>/2`), so it uses no `Ash` module, and the boundaries hold.
- With no Tailwind, and a small stylesheet in its place, a browser showed the
  filters, the list of choices, the sort, the pages and the clear buttons at
  work, in the light and in the dark scheme, with no error in the console.

## Decision

- **A collection of records is a `Cinder.collection`.** We do not write a
  table with filters, a sort or pages by hand.
- Cinder is a dependency from Hex, added by hand, with no installer.
  `assets/js/app.js` imports its colocated hooks.
- **We still write no LiveComponent.** The one inside Cinder is its own.
- `RescordWeb.CinderTheme` is the theme of each collection, set in
  `config :cinder, default_theme:`. It sets each class to the empty string.
  It names a class only for a part or a state that Cinder marks in no other
  way (`CinderTheme.marks/0`).
- **The stylesheet gets a layer `vendor`**, in `assets/css/layers/vendor.css`,
  after `components`. Its role is the markup that a dependency renders.
  - It styles a part of Cinder by its `data-key` attribute, which Cinder
    writes on most parts.
  - It is the one file that may select a class: a class that Cinder writes
    into its markup itself, or a mark of the theme, and only below the root
    element of Cinder.
  - It gives a rule to each class of Cinder that carries behaviour
    (`hidden`, `invisible`, `sr-only`), and it draws the four icons that
    Cinder names. The Tailwind classes that only lay a part out get no rule.
  - It does not dim a part while a result loads, although Cinder asks for
    that: dimmed text falls below a contrast of 4.5:1. The overlay of Cinder
    says that a result loads.
- The markup that we write stays classless, inside a slot of Cinder too.
- A page passes `query={...}` from the code interface of a domain, with the
  actor and the tenant, and never `resource={...}`.
- `RescordWeb.CinderTest` holds the three together: the theme, the classes
  in the markup of Cinder, and the rules of `vendor.css`.

## Consequences

- ADR 0004 has one exception, in one file, for markup that we do not write.
  ADR 0007 has a sixth layer, for a new role.
- An upgrade of Cinder can change its markup. The test fails for a class
  that it does not know. Then read what the class does, and give it a rule or
  add it to the list of layout classes. Look at a page in a browser too: no
  test here runs a browser.
- `vendor.css` covers what we saw in the trial: the table, the list and the
  grid; the text, choice, yes or no and date range filters; the search; the
  sort; the pages. A filter of another type, the selection of rows and the
  actions on them have rules that no browser has shown yet.
- **The markup of Cinder has gaps in accessibility**, which we cannot close
  from a stylesheet:
  - The sort of a table column is a `div` with a click. It takes no focus
    from the keyboard, and the `th` has no `aria-sort` and no `scope`. The
    sort buttons of a list and of a grid are real buttons.
  - The choice filter is a button and a list of radio buttons, with no
    `aria-expanded` and no role for the list.
  - The pages are not a `nav`, and the current page has no `aria-current`.
  These are changes to give back to Cinder. Until then, a table whose sort
  must work from the keyboard needs another way to sort.
- The names of the icons in the markup are those of Heroicons. We have no
  icon library; `vendor.css` draws the four shapes.
- The first resource in the schema of an organisation needs
  `Rescord.Repo.all_tenants/0`, or `mix ash.setup` stops. The trial found
  this; it is not about Cinder.
