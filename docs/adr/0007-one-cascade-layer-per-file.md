# ADR 0007: The stylesheet is one cascade layer per file, and a layer is a role

Status: accepted (asked for by the maintainer); amends ADR 0004

## Context

ADR 0004 put the whole classless stylesheet in `assets/css/app.css`, as
eleven sections under comment banners. The maintainer asked for one file per
layer.

The first split made each section a CSS cascade layer, twelve with the
colocated CSS. The maintainer asked whether that many layers is the usual
practice. It is not. The sources that we read show a few layers, each for a
role:

- Chrome's article on cascade layers declares
  `@layer base, theme, layouts, components, utilities;`, recommends the order
  of ITCSS, "from least to most specific", and imports several component
  files into the one `components` layer.
- MDN's guide starts with `@layer theme, layout, utilities;`, and says:
  "Specificity still matters for competing property values within a layer,
  but there are no specificity concerns between layers."

Neither source gives a number, and MDN also allows a layer per component. So
twelve layers were valid, but they were sections and not roles: two sections
of the same role, such as buttons and forms, then needed a place in the order
that only one rule (a disabled button) decided.

## Decision

- A layer stands for a role, and each layer is one file in
  `assets/css/layers/`:

  | Layer | File | Role |
  | --- | --- | --- |
  | `tokens` | `tokens.css` | the custom properties that the other layers read |
  | `base` | `base.css` | box sizing, the page, the focus ring, reduced motion |
  | `elements` | `elements.css` | the default look of each HTML element: text, lists, tables, forms, buttons |
  | `layout` | `layout.css` | the landmarks of a page, the site nav, the skip link, the page header |
  | `components` | `components.css` | the parts that an attribute marks: icons, flash messages |
  | `colocated` | none | the CSS that a component writes next to its markup (`Phoenix.LiveView.ColocatedCSS`) |

- `app.css` holds no rule. It states the order in one `@layer` statement,
  and imports each file into its layer with
  `@import "./layers/NAME.css" layer(NAME)`. esbuild bundles the imports.
- The order runs from the least specific role to the most. A later layer
  wins over an earlier one whatever the specificity. Inside one layer,
  specificity and order decide as usual, and a file keeps its sections under
  comment banners.
- No rule is outside a layer. A rule outside a layer would win over every
  layer.
- A new rule goes in the file of its layer. Add a layer only for a new role,
  such as utilities; a new component is a section of `components.css`.

## Consequences

- The split changed nothing that a page draws. A browser read the computed
  style of each of 144 elements of a page that holds every component, in a
  light and a dark scheme, at a desktop and a phone width, before and after.
  The only difference was white space inside one custom property, and the
  four screenshots were the same byte for byte.
- `elements.css` is the long file, about 350 lines. If a layer's file grows
  hard to read, split it into several files that are all imported into that
  one layer, as Chrome's article does. Do not add a layer for it.
- An `!important` rule runs the other way: one in an earlier layer wins over
  one in a later layer. Only `base` has such rules (`[hidden]` and reduced
  motion), which is the layer that should win them.
- We could not read the guide to cascade layers on CSS-Tricks, which refused
  the request, so this decision does not rest on it.
