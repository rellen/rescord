// The sort of a table column of Cinder, for a keyboard and a screen reader
// (ADR 0017).
//
// Cinder renders the sort control of a column as a `div` with a click. It
// takes no focus from the keyboard, and the header cell says nothing about
// the sort. This module makes up for both in the browser:
//
//   - the control becomes a button that takes the focus, and Enter or Space
//     presses it;
//   - the header cell gets `scope="col"`, and `aria-sort` while its column
//     is sorted.
//
// LiveView patches the table from markup that has none of these attributes.
// `app.js` therefore calls `keep` before LiveView updates an element, so a
// control keeps its focus, and `enhance` after every patch, for a table
// that is new.
//
// `RescordWeb.CinderTest` holds the selectors and the two icon classes below
// to the markup that Cinder renders.

const HEADER = '[data-key="th_class"]';
const SORT = '[phx-click="toggle_sort"]';
const CONTROL = `${HEADER} > ${SORT}`;

type Direction = "ascending" | "descending";

// Cinder says the direction only with the icon inside the control.
function direction(control: Element): Direction | null {
  if (control.querySelector(".hero-chevron-up")) return "ascending";
  if (control.querySelector(".hero-chevron-down")) return "descending";
  return null;
}

function markControl(control: HTMLElement): void {
  control.setAttribute("role", "button");
  control.tabIndex = 0;
}

function markHeader(header: Element): void {
  const control = header.querySelector<HTMLElement>(`:scope > ${SORT}`);
  const sorted = control && direction(control);

  header.setAttribute("scope", "col");

  if (sorted) {
    header.setAttribute("aria-sort", sorted);
  } else {
    header.removeAttribute("aria-sort");
  }

  if (control) markControl(control);
}

/** Marks each header cell of Cinder below `root`, and its sort control. */
export function enhance(root: ParentNode = document): void {
  root.querySelectorAll(HEADER).forEach(markHeader);
}

/**
 * Marks the element that LiveView is about to put in the place of `from`, so
 * that the patch takes no attribute of ours off the page. `to` is not in the
 * page yet, so `from` says what it is.
 */
export function keep(from: Element, to: Element): void {
  if (from.matches(HEADER)) {
    markHeader(to);
  } else if (from.matches(CONTROL)) {
    markControl(to as HTMLElement);
  }
}

/** Presses a sort control with Enter or Space, as a button does. */
export function listen(target: Document = document): void {
  target.addEventListener("keydown", (event: KeyboardEvent) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    if (!(event.target instanceof HTMLElement) || !event.target.matches(CONTROL)) return;

    // Space would scroll the page.
    event.preventDefault();
    event.target.click();
  });
}
