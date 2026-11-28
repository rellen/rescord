// Keeps the focus of the keyboard in its place when LiveView changes the
// page (ADR 0090).
//
// Two things took the focus away, and gave it to the top of the page, where
// a person who uses the keyboard or a screen reader starts again:
//
//   - A press on a button that the next render does not have. The button
//     Done of a task is one: the task then has the button Open again.
//     LiveView puts a new row in the place of the old one, and the browser
//     drops the focus when its element leaves the page.
//   - A link to another live page. LiveView puts the new page in the place
//     of the old one, with no load of a document, so the browser announces
//     nothing and the focus is on nothing.
//
// `watch` notes the element that has the focus, with the parts of the page
// around it. `restore` runs after each patch: when that element is gone and
// nothing has the focus, the focus goes to the first control of the nearest
// part that is still there. A part that was put in again is found by its
// `id`, so the focus stays in the row of the button and does not go to the
// first row of the table. `listen` moves the focus to the heading of a new
// live page, which a screen reader then reads.
//
// Neither moves the focus when the page still has it.

const CONTROLS =
  'a[href], button:not([disabled]), input:not([type="hidden"], [disabled]), ' +
  'select:not([disabled]), textarea:not([disabled]), summary, [tabindex]:not([tabindex="-1"])'

// A part of the page around the element that has the focus: the element,
// and its `id` when it has one.
type Part = {element: Element; id: string}

// The element that has the focus, and then the parts around it, from the
// nearest one out. Empty when nothing has the focus.
let trail: Part[] = []

function inPage(element: Element): boolean {
  return element.isConnected && element.getClientRects().length > 0
}

function lost(): boolean {
  const active = document.activeElement
  return !active || active === document.body
}

// The part as the page has it now: the same element, or the element that
// took its place with the same `id`.
function now(part: Part): Element | null {
  if (inPage(part.element)) return part.element

  const again = part.id ? document.getElementById(part.id) : null
  return again && inPage(again) ? again : null
}

// Gives the focus to an element that takes none from the Tab key, such as
// a heading or a cell.
function focusPlace(element: HTMLElement): void {
  if (!element.hasAttribute("tabindex")) element.setAttribute("tabindex", "-1")
  element.focus({preventScroll: true})
}

function focusHeading(): void {
  const heading = document.querySelector<HTMLElement>("main h1")
  if (heading) focusPlace(heading)
}

/** Notes the element that has the focus, and forgets it when a person takes the focus away. */
export function watch(target: Document = document): void {
  target.addEventListener("focusin", (event: FocusEvent) => {
    trail = []

    for (let part = event.target as Element | null; part && part !== document.body; part = part.parentElement) {
      trail.push({element: part, id: part.id})
    }
  })

  // A person who presses beside the controls takes the focus away, and the
  // element is still in the page afterwards. An element that leaves the
  // page is the case that `restore` puts right. The browser sends the event
  // for both, so look when the change of the page is over.
  target.addEventListener("focusout", (event: FocusEvent) => {
    const left = event.target

    window.setTimeout(() => {
      if (left instanceof Element && inPage(left) && lost()) trail = []
    }, 0)
  })
}

// Gives the focus to the place that the trail names: the element that took
// the place of the one with the focus, or the first control of the nearest
// part that the page still has, or that part itself when it has no control.
// Says if it found a place. The whole page is no place: its first control
// is the top of the page again.
function backToPlace(): boolean {
  const [had, ...parts] = trail
  trail = []

  if (!had) return false

  const again = had.id ? document.getElementById(had.id) : null

  if (again instanceof HTMLElement && inPage(again)) {
    again.focus()
    return true
  }

  const part = parts.map(now).find((element) => element !== null)
  if (!(part instanceof HTMLElement) || part.matches("main, [data-phx-main]")) return false

  const control = Array.from(part.querySelectorAll<HTMLElement>(CONTROLS)).find(inPage)

  if (control) {
    control.focus()
  } else {
    focusPlace(part)
  }

  return true
}

/**
 * Puts the focus back after a patch, when the element that had it is gone
 * and nothing has the focus. With no place near, the focus goes to the
 * heading of the page.
 */
export function restore(): void {
  const had = trail[0]

  if (!had || inPage(had.element) || !lost()) return
  if (!backToPlace()) focusHeading()
}

/**
 * Gives the focus its place on a live page that took the place of another
 * one. A page that the browser loads as a document needs nothing: the
 * browser announces it.
 *
 * A new page gets the focus on its heading, which a screen reader then
 * reads. A page that loads itself again after an action, as the tasks do
 * after Done, gets the focus back where it was: in the row of the button.
 */
export function listen(target: Window = window): void {
  // LiveView says that the old page goes, and then that the new one is
  // there. Only then does the page have its new elements.
  let arriving: "no" | "new" | "same" = "no"

  target.addEventListener("phx:page-loading-start", (event: Event) => {
    const detail = (event as CustomEvent<{kind?: string; to?: string}>).detail
    if (detail?.kind !== "redirect") return

    // The address is still the one of the old page here.
    const to = new URL(detail.to || "", window.location.href).href
    arriving = to === window.location.href ? "same" : "new"
  })

  target.addEventListener("phx:page-loading-stop", () => {
    if (arriving === "no" || !document.querySelector("main h1")) return

    const same = arriving === "same"
    arriving = "no"

    if (same && backToPlace()) return

    trail = []
    focusHeading()
  })
}
