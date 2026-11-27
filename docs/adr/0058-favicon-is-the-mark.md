# ADR 0058: The icon of the tab is the mark of the site bar

Status: accepted (the maintainer asked for it on 27 November 2026; the
drawing and the colours are a first choice).

## Context

The site bar shows the mark of Rescord beside its name: a square with round
corners and a plus in it, in the lead colour (`CoreComponents.icon/1`,
`name="mark"`). The tab of a browser showed nothing: `favicon.ico` was an
empty image, and no page linked an icon.

The mark is drawn on a grid of 24 with a line of 2. At the 16 pixels of a
tab that line is 1.3 pixels wide and falls between the pixels, so the mark
is small and soft. The lead colour has two values, one for each scheme, and
neither reads on the ground of the other: the dark value has a contrast of
1.8 to 1 on white.

## Decision

- **`priv/static/images/favicon.svg` is the mark, drawn again on a grid of
  16** with the same line of 2: the same square, the same plus and the same
  round ends. Each line falls on whole pixels at 16, 32 and 48 pixels, and
  the mark fills the icon.
- **The favicon follows the colour scheme.** Its style holds the two values
  of the token `accent`, and a media query on `prefers-color-scheme` chooses
  one. `RescordWeb.FaviconTest` holds the two values to `tokens.css`.
- **`priv/static/favicon.ico` is for a client that takes no SVG icon.** It
  holds a PNG of 16, of 32 and of 48 pixels. An ICO cannot follow the
  scheme, so it has one green between the two values, `#298e7e`. That green
  has a contrast of 3 to 1 or more on white, on `#dee1e6`, on `#202124` and
  on `#35363a`, which is about the range of a light and of a dark tab bar.
- **`priv/static/images/apple-touch-icon.png` is for a home screen**: 180
  pixels, the mark in the light value on white. It has no transparent
  part, which iOS draws in black, and no round corners, which iOS cuts
  itself.
- **The root layout links the three.** The SVG and the PNG are under
  `images/`, which `RescordWeb.static_paths/0` already serves, and their
  links have a digest in a release. The ICO stays at the root, where a
  browser asks for it by name, and its link is the plain path:
  `Plug.Static` does not serve the digest name of a file at the root.
- **`scripts/favicons.sh` draws the ICO and the PNG from the SVG** with
  libvips, which the devenv shell has. The three files are in the
  repository, so a build does not run the script.

## Consequences

- The mark has two drawings: the icon in `CoreComponents` and the favicon.
  A change to one is a change to the other by hand, and then
  `scripts/favicons.sh` writes the other two files again.
- There is no web manifest, so a phone with Android has these three icons
  to choose from. A manifest arrives if Rescord becomes an application
  that a phone installs.
- A browser that reads the scheme of the system for an SVG icon, and has a
  tab bar of the other scheme, shows the mark in the less clear of the two
  values.
- A browser keeps an icon for a long time. After an upgrade, a tab can show
  the old one until the browser asks again.
