// The menu of the site is a popover on a narrow screen (ADR 0061). The
// browser closes it on Escape and on a press outside it, but not when the
// Tab key takes the focus out of it: the open menu then covers the control
// that has the focus (WCAG 2.4.11). `listen` closes it then (ADR 0111).

function open(popover: HTMLElement): boolean {
  try {
    return popover.matches(":popover-open")
  } catch {
    // A browser with no popovers knows no such state.
    return false
  }
}

/** Closes an open popover when the focus goes to a control outside it and its button. */
export function listen(target: Document = document): void {
  target.addEventListener("focusin", (event: FocusEvent) => {
    const focused = event.target

    if (!(focused instanceof Node)) return

    for (const popover of target.querySelectorAll<HTMLElement>("[popover][id]")) {
      if (!open(popover) || popover.contains(focused)) continue

      const opener = target.querySelector(`[popovertarget="${CSS.escape(popover.id)}"]`)
      if (!opener?.contains(focused)) popover.hidePopover()
    }
  })
}
