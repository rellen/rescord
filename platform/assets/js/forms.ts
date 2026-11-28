// The forms of a person who types (ADR 0111).
//
//   - A form in a <details>: when a person opens it from its summary, the
//     focus goes to its first field, so they type at once. A <details>
//     that LiveView opens again after a patch (ADR 0031) keeps the focus
//     where it is: only a toggle while its summary has the focus counts.
//   - Ctrl or Cmd with Enter in a text area sends its form, as Enter does in
//     a field of one line. The form of Ruby sends on Enter alone (ADR 0069).

const FIELDS =
  'input:not([type="hidden"], [disabled]), select:not([disabled]), textarea:not([disabled])'

function shows(element: Element): boolean {
  if (element.getClientRects().length === 0) return false
  return typeof element.checkVisibility !== "function" || element.checkVisibility({visibilityProperty: true})
}

/** Listens, on the whole page, for an open of a form and for Ctrl+Enter. */
export function listen(target: Document = document): void {
  // A toggle does not bubble, so the page hears it on the way down.
  target.addEventListener(
    "toggle",
    (event: Event) => {
      const details = event.target
      if (!(details instanceof HTMLDetailsElement) || !details.open) return

      const summary = details.querySelector(":scope > summary")
      if (!summary || target.activeElement !== summary) return

      const form = Array.from(details.querySelectorAll("form")).find((form) => form.closest("details") === details)
      const field = form && Array.from(form.querySelectorAll<HTMLElement>(FIELDS)).find(shows)
      field?.focus()
    },
    true
  )

  target.addEventListener("keydown", (event: KeyboardEvent) => {
    if (event.key !== "Enter" || !(event.ctrlKey || event.metaKey) || event.isComposing) return

    const field = event.target
    if (!(field instanceof HTMLTextAreaElement) || !field.form) return

    event.preventDefault()
    field.form.requestSubmit()
  })
}
