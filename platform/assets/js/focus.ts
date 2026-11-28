// Keeps the focus of the keyboard in its place when LiveView changes the
// page (ADR 0090, ADR 0111).
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
// `id`, or a row of a collection by the record that it shows
// (`data-item-id`), so the focus stays in the row of the button and does not
// go to the first row of the table. `listen` moves the focus to the heading
// of a new live page, which a screen reader then reads.
//
// LiveView can keep the element of a row and put another record in it. A
// button there then acts on the other record, so the focus leaves it even
// when the page still has the focus: it goes to the row of its record, or,
// when that record is gone, to the heading of the collection (ADR 0111).
//
// Otherwise neither moves the focus when the page still has it.

const CONTROLS =
  'a[href], button:not([disabled]), input:not([type="hidden"], [disabled]), ' +
  'select:not([disabled]), textarea:not([disabled]), summary, [tabindex]:not([tabindex="-1"])'

// The parts of a table that are no place for the focus: their first control
// is the first row, which shows another record.
const TABLE_PARTS = "table, thead, tbody, tfoot, tr"

// A part of the page around the element that has the focus: the element,
// and what names it, when anything does. `record` says that the name is the
// record of a row, which another record can take the place of.
type Part = {element: Element; name: string | null; record: boolean}

// The element that has the focus, and then the parts around it, from the
// nearest one out. Empty when nothing has the focus.
let trail: Part[] = []

// The time of the last press of a pointer, to tell a press beside the
// controls from a change of the page.
let pressedAt = -Infinity

function part(element: Element): Part {
  if (element.id) return {element, name: `#${CSS.escape(element.id)}`, record: false}

  const item = element.getAttribute("data-item-id")
  if (item) return {element, name: `[data-item-id="${CSS.escape(item)}"]`, record: true}

  return {element, name: null, record: false}
}

// Says if a person can see the element and give it the focus: it is in the
// page, it has a box, and it is not hidden, nor inside a closed <details>.
// A browser with no `checkVisibility` counts the box only.
function inPage(element: Element): boolean {
  if (!element.isConnected || element.getClientRects().length === 0) return false

  return typeof element.checkVisibility !== "function" || element.checkVisibility({visibilityProperty: true})
}

function lost(): boolean {
  const active = document.activeElement
  return !active || active === document.body
}

// Says if LiveView kept the element of the part in the page and put
// another thing in it: the element has another name now.
function reused(part: Part): boolean {
  return part.name !== null && part.element.isConnected && !part.element.matches(part.name)
}

// The part as the page has it now: the same element, or the element that
// took its place with the same name.
function now(part: Part): Element | null {
  if (!reused(part) && inPage(part.element)) return part.element

  const again = part.name ? document.querySelector(part.name) : null
  return again && inPage(again) ? again : null
}

// The index of the outermost part that LiveView reused for another thing:
// the parts inside it are no place for the focus. -1 when there is none.
function outermostReused(): number {
  for (let index = trail.length - 1; index >= 0; index--) {
    if (reused(trail[index])) return index
  }

  return -1
}

// Says if the row of a collection around the focus shows another record now.
function rowReused(): boolean {
  return trail.some((part) => part.record && reused(part))
}

// Gives the focus to the element, and says if it took it.
function give(element: HTMLElement): boolean {
  element.focus()
  return document.activeElement === element
}

// Gives the focus to an element that takes none from the Tab key, such as
// a heading or a cell.
function focusPlace(element: HTMLElement): boolean {
  if (!element.hasAttribute("tabindex")) element.setAttribute("tabindex", "-1")
  element.focus({preventScroll: true})
  return document.activeElement === element
}

// The heading of the page, or the field that a page names with `autofocus`:
// a form that the person goes on with, such as the measurement after a
// measurement (ADR 0111). A browser gives that field the focus on a load of
// a document, and this does it on a live page.
function focusHeading(): void {
  const field = Array.from(document.querySelectorAll<HTMLElement>("main [autofocus]")).find(inPage)
  if (field && give(field)) return

  const heading = document.querySelector<HTMLElement>("main h1")
  if (heading) focusPlace(heading)
}

// The heading of the collection around the element: the heading that names
// its section (ADR 0087).
function collectionHeading(element: Element): HTMLElement | null {
  const section = element.closest("section[aria-labelledby]")
  const id = section?.getAttribute("aria-labelledby")
  return id ? document.getElementById(id) : null
}

/** Notes the element that has the focus, and forgets it when a person takes the focus away. */
export function watch(target: Document = document): void {
  target.addEventListener("focusin", (event: FocusEvent) => {
    trail = []

    for (let element = event.target as Element | null; element && element !== document.body; element = element.parentElement) {
      trail.push(part(element))
    }
  })

  target.addEventListener("pointerdown", () => (pressedAt = performance.now()), true)

  // A person who presses beside the controls takes the focus away, and the
  // element is still in the page afterwards. The browser also drops the
  // focus when LiveView moves the element, or hides it, or makes it
  // disabled: that is the case that `restore` puts right. Only a press of a
  // pointer just before tells the two apart.
  target.addEventListener("focusout", (event: FocusEvent) => {
    const left = event.target

    window.setTimeout(() => {
      const pressed = performance.now() - pressedAt < 1000
      if (pressed && left instanceof Element && inPage(left) && lost()) trail = []
    }, 0)
  })
}

// Gives the focus to the place that the trail names: the element that had
// it, or the one that took its place, or the first control of the nearest
// part that the page still has, or that part itself when it has no control.
// A part inside one that LiveView gave to another record is no place. When
// the record of a row is gone, the focus goes to the heading of the
// collection. Says if it found a place. The whole page is no place: its
// first control is the top of the page again.
function backToPlace(): boolean {
  const from = Math.max(outermostReused(), 0)
  const index = trail.findIndex((part, at) => at >= from && now(part) !== null)
  const place = index >= 0 ? now(trail[index]) : null
  // A row between the focus and its new place: the record of the focus is
  // not in the collection now.
  const rowLeft = trail.slice(0, Math.max(index, 0)).some((part) => part.record)
  trail = []

  if (!(place instanceof HTMLElement) || place.matches("main, [data-phx-main]")) return false
  if (index === 0) return give(place)

  if (rowLeft || place.matches(TABLE_PARTS)) {
    const heading = collectionHeading(place)
    if (heading) return focusPlace(heading)
  }

  const control = Array.from(place.querySelectorAll<HTMLElement>(CONTROLS)).find(inPage)
  return control ? give(control) : focusPlace(place)
}

/**
 * Puts the focus back after a patch: when the element that had it is gone
 * or hidden and nothing has the focus, and when LiveView put another record
 * in its row. With no place near, the focus goes to the heading of the page.
 */
export function restore(): void {
  const had = trail[0]

  if (!had || !(lost() || rowReused())) return
  // A button that waits for the answer of the server is disabled for a
  // while: the patch that enables it again puts the focus back on it.
  if (lost() && had.element.isConnected && had.element.matches(":disabled")) return
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
