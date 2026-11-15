# ADR 0015: The look is the design direction Scrubs

Status: accepted (chosen by the maintainer, 15 November 2026)

## Context

The stylesheet had the colours of a neutral starting point. The maintainer
asked for a look that fits a system for a rescue or a refuge, in medical
green, red and blue, with a light and a dark scheme. Three directions were
drawn, each as a set of tokens and the same two screens:
https://claude.ai/artifact/QsusUupcST7GFjqc4Mxh8o. The maintainer chose
Scrubs: a veterinary practice, where surgical green leads on a soft mint
ground, with round corners and a typeface drawn for legibility.

## Decision

- `assets/css/layers/tokens.css` holds the values of Scrubs. Each colour is
  `light-dark(light, dark)` and follows the scheme of the system.
- **A colour has one meaning.** Green (`ok`) is well and done. Red (`alert`)
  is what needs somebody now. Blue (`info`, `link`, `focus`) is information,
  a link and the keyboard focus. The lead colour (`accent`) is the primary
  action, the current page and a ticked box.
- **A state is a shape and a word, never the colour alone.**
  `<.state kind="ok">In care</.state>` renders an icon and the word in a
  `span[data-state]`.
- **There are three grounds, one above the other.** `bg` is the page,
  `surface` is a card on it, and `raised` is a menu or a list of choices
  above a card. An `article` is a card, and so is a form that a page or a
  section holds. `selected` is the ground of a selected row and of the
  chosen option. `tint` is a faint ground over whatever is below it: a
  hover, a piece of code.
- `field` is the edge of a control, and `focus` is the ring of the keyboard
  focus. Both have a contrast of 3 to 1 or more on each ground.
- **Only `tokens.css` writes a colour.** Each other layer reads a token.
- The typeface is Atkinson Hyperlegible, under the SIL Open Font License.
  The application serves the font files itself, from
  `priv/static/fonts/atkinson-hyperlegible`, with the licence beside them.
  No page loads a font from another host.
- A button is a pill, a card and a field have corners of 12px, and the type
  scale is that of an application: a body of 15px, and headings from 24px
  down.
- `RescordWeb.TokensTest` reads `tokens.css` and holds each pair of a text
  and its ground to 4.5 to 1, and of an edge, a ring or an icon and its
  ground to 3 to 1, in both schemes. It also refuses a colour in any other
  layer.

## Consequences

- The tokens `danger` and `danger-surface` are now `alert` and
  `alert-surface`. `surface` changed its meaning: it was the tinted ground of
  a panel, and it is now the ground of a card, lighter than the page.
- A new pair of a colour and a ground in a layer takes a line in
  `RescordWeb.TokensTest`. The test cannot find a pair that nobody lists.
- The drawing of Scrubs also has a row of counts and a journal list. Their
  rules are in the drawing and not in the stylesheet: they arrive with the
  pages that need them.
- The font files are the Latin and the extended Latin subsets, in two weights
  and two styles: eight files, about 110 kB together. A script outside those
  subsets takes the next font of the stack.
- The bar that LiveView shows while a page loads keeps its blue, which
  `assets/js/app.js` sets. It is not a token.
- No test runs a browser. A browser showed the collection, a form with an
  error, the states and a grid of cards, in both schemes, on the day of this
  record.
