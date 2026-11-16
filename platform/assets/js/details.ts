// Keeps a <details> open when LiveView patches the page.
//
// A person opens a <details>, and the browser sets its `open` attribute. The
// server does not know that: its next render has no `open`, so the patch
// would close the element, and hide a form that the person is filling in.
// `keepOpen` runs before each element is updated, and carries the state over.

/** Carries the open state of a <details> from the page to its new render. */
export function keepOpen(from: Element, to: Element): void {
  if (from instanceof HTMLDetailsElement && to instanceof HTMLDetailsElement && from.open) {
    to.open = true
  }
}
