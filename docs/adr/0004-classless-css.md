# ADR 0004: Semantic HTML with a classless stylesheet

Status: accepted (chosen by the maintainer: "strive for classless")

## Context

`mix phx.new` generates Tailwind with daisyUI, Heroicons, and core components
written in utility classes, plus an `AGENTS.md` that tells agents to use
Tailwind. The project wants semantic, accessible HTML, and CSS that does not
leak into the markup.

## Decision

- Remove Tailwind, daisyUI and Heroicons, with their dependencies, config and
  watcher, and the generated `AGENTS.md`. `CLAUDE.md` holds the conventions.
- One hand-written stylesheet, `assets/css/app.css`, which esbuild bundles
  next to `app.js`. It styles elements, ARIA states and roles (for example
  `[aria-invalid="true"]`, `[aria-current="page"]`), and a few `data-`
  attributes for variants that no element or state expresses
  (`data-variant`, `data-flash`, `data-spin`). It never selects a class.
- Colours follow the system's light or dark scheme with `light-dark()`.
  There is no theme switch.
- The page's landmarks centre their content with padding, so the layout
  needs no wrapper elements.
- `CoreComponents` keeps the attributes and slots of the generated
  components, and renders classless markup: a skip link, `role="alert"` for an
  error flash and `role="status"` for an information, `<th scope="col">`,
  `aria-invalid` and `aria-describedby` on a control with errors, `<hgroup>`
  in the page header, and `<dl>` for a data list.
- Icons are our own inline SVGs in `CoreComponents.icon/1`, `aria-hidden`.
  An unknown literal icon name gives a compile warning.

## Consequences

- Generated code (`phx.gen.*`, Ash generators) still has Tailwind classes and
  Heroicon names, and must be restyled by hand.
- `CoreComponentsTest` and `PageControllerTest` assert that the markup has no
  `class` attribute.
- The stylesheet uses `:has()`, `light-dark()` and media query ranges, which
  current browsers support.
