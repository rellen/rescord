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
// The module also says what the other controls of a collection are
// (ADR 0087):
//
//   - a button that opens a list, which is the choice filter and the size
//     of a page, says if the list is open (`aria-expanded`) and which
//     list it is (`aria-controls`), and the Escape key closes the list;
//   - an arrow key moves through the choices of a filter and the list
//     stays open; Enter closes it; the list closes when the focus leaves
//     it; and the focus goes back to the button when the list closes
//     under it;
//   - the list of a choice filter is a group of radio buttons with the
//     name of the filter, and the list of the sizes is a group;
//   - the pages are a navigation landmark, the page that shows is
//     `aria-current`, and each button has its words as its name;
//   - a button whose text is a sign, such as the "×" that clears a filter,
//     has the words of its title as its name, and a drawing of Cinder is
//     hidden from a screen reader;
//   - a table has the name of its section, or of the page;
//   - a collection says that it loads (`aria-busy`), and a status region
//     says the new count after a filter, a search or a change of page.
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

// A button that opens a list, and the list, which is the next element.
const CHOICE = '[data-key="filter_select_input_class"]';
const SIZE = '[data-key="page_size_dropdown_class"]';
const OPENER = `${CHOICE}, ${SIZE}`;
const LIST =
  '[data-key="filter_select_dropdown_class"], [data-key="page_size_dropdown_container_class"]';
const SIZE_WORDS = '[data-key="page_size_label_class"]';

// The pages.
const PAGES = '[data-key="pagination_nav_class"]';
const PAGE_NOW = '[data-key="pagination_current_class"]';

function words(element: Element | null): string {
  return (element?.textContent ?? "").replace(/\s+/g, " ").trim();
}

function listOf(opener: Element): HTMLElement | null {
  const list = opener.nextElementSibling;
  return list instanceof HTMLElement && list.matches(LIST) ? list : null;
}

function shows(list: HTMLElement): boolean {
  return getComputedStyle(list).display !== "none";
}

function markOpener(opener: Element): void {
  const list = listOf(opener);
  if (!list) return;

  if (list.id) opener.setAttribute("aria-controls", list.id);
  opener.setAttribute("aria-expanded", shows(list) ? "true" : "false");

  if (opener.matches(CHOICE)) {
    // The label of the filter names the button, and the list too.
    const label = opener.id ? document.querySelector(`label[for="${CSS.escape(opener.id)}"]`) : null;

    list.setAttribute("role", "radiogroup");

    if (label) {
      // The label alone would name the button, and hide the choice on it.
      opener.setAttribute("aria-label", `${words(label)}: ${words(opener)}`);
      list.setAttribute("aria-label", words(label));
    }
  } else {
    // "Show", the number on the button, "per page".
    const parts = opener.closest('[data-key="page_size_container_class"]');
    const [before, after] = parts ? Array.from(parts.querySelectorAll(SIZE_WORDS)) : [];
    const name = [words(before ?? null), words(opener), words(after ?? null)].filter(Boolean).join(" ");

    opener.setAttribute("aria-label", name);
    list.setAttribute("role", "group");
    list.setAttribute("aria-label", name);
  }
}

function markPages(pages: Element): void {
  pages.setAttribute("role", "navigation");
  pages.setAttribute("aria-label", "Pages");

  pages.querySelectorAll(PAGE_NOW).forEach((now) => now.setAttribute("aria-current", "page"));
}

// A collection, and the parts of it that the marks below read.
const COLLECTION = '[data-key="container_class"]';
const CLEAR_ONE = '[data-key="filter_clear_button_class"]';
const FILTER = '[data-key="filter_input_wrapper_class"]';
const LOADING = '[data-key="loading_overlay_class"]';
const EMPTY = '[data-key="empty_class"]';
const PAGE_INFO = '[data-key="pagination_info_class"]';
const ITEM = '[data-item-id], [data-key$="_item_class"]';

// The text of such a button is a sign: "×", a number, an arrow. Its title
// has the words, and the button that clears one filter says which.
function nameButton(button: Element): void {
  const title = button.getAttribute("title");
  if (!title) return;

  const label = button.matches(CLEAR_ONE) ? words(button.closest(FILTER)?.querySelector("label") ?? null) : "";
  const named = label === "" || title.toLowerCase().includes(label.toLowerCase());

  button.setAttribute("aria-label", named ? title : `${title}: ${label}`);
}

// The name of a table: the heading of its section, or the heading of the
// page.
function nameTable(table: Element): void {
  const section = table.closest("section[aria-labelledby]");

  if (section) {
    table.setAttribute("aria-labelledby", section.getAttribute("aria-labelledby") ?? "");
  } else {
    const heading = words(document.querySelector("main h1"));
    if (heading) table.setAttribute("aria-label", heading);
  }
}

// What a collection shows now, in words: the line of its pages, its empty
// state, or the count of its rows. Nothing while it loads.
function summary(collection: Element): string | null {
  if (collection.querySelector(LOADING)) return null;

  const info = collection.querySelector(PAGE_INFO);
  if (info) return words(info);

  const empty = collection.querySelector(EMPTY);
  if (empty) return words(empty);

  const count = collection.querySelectorAll(ITEM).length;
  return count === 1 ? "1 result" : `${count} results`;
}

// What each collection said last, and the one region of the page that
// says a change. The region is outside the markup of LiveView, so no
// patch takes it away.
const said = new WeakMap<Element, string>();

function region(): HTMLElement {
  const there = document.querySelector<HTMLElement>("[data-cinder-status]");
  if (there) return there;

  const made = document.createElement("div");
  made.setAttribute("role", "status");
  made.setAttribute("data-cinder-status", "");
  document.body.append(made);
  return made;
}

function markCollection(collection: Element): void {
  collection.querySelectorAll("button[title]").forEach(nameButton);
  collection.querySelectorAll("table").forEach(nameTable);

  collection.querySelectorAll("svg:not([aria-hidden])").forEach((drawing) => {
    drawing.setAttribute("aria-hidden", "true");
    drawing.setAttribute("focusable", "false");
  });

  const now = summary(collection);

  if (now === null) {
    collection.setAttribute("aria-busy", "true");
    return;
  }

  collection.removeAttribute("aria-busy");

  // The first result of a collection is the page itself: say only a change.
  const before = said.get(collection);
  said.set(collection, now);
  if (before !== undefined && before !== now) region().textContent = now;
}

/**
 * Marks the controls of each collection of Cinder below `root`: the header
 * cells and their sort controls, the buttons that open a list, the pages,
 * and the collection itself.
 */
export function enhance(root: ParentNode = document): void {
  root.querySelectorAll(HEADER).forEach(markHeader);
  root.querySelectorAll(OPENER).forEach(markOpener);
  root.querySelectorAll(PAGES).forEach(markPages);
  root.querySelectorAll(COLLECTION).forEach(markCollection);
}

/**
 * Follows a list that opens or closes. LiveView shows and hides it in the
 * browser, with no patch, so nothing else says that its button changed.
 */
export function watch(target: Document = document): void {
  // The list that had the focus last. When it closes, the browser drops
  // the focus, and a person with a keyboard starts again at the top.
  let focused: HTMLElement | null = null;

  target.addEventListener("focusin", (event: FocusEvent) => {
    const list = event.target instanceof Element ? event.target.closest(LIST) : null;
    focused = list instanceof HTMLElement ? list : null;
  });

  // The focus left an open list for a thing that is not its button: close
  // the list, in the way of Cinder.
  target.addEventListener("focusout", (event: FocusEvent) => {
    const list = event.target instanceof Element ? event.target.closest(LIST) : null;
    const next = event.relatedTarget;

    if (!(list instanceof HTMLElement) || !(next instanceof Node)) return;
    if (list.contains(next) || list.previousElementSibling === next) return;

    const opener = list.previousElementSibling;
    if (opener instanceof HTMLElement && opener.matches(OPENER) && shows(list)) opener.click();
  });

  const observer = new MutationObserver((changes) => {
    for (const change of changes) {
      if (!(change.target instanceof HTMLElement) || !change.target.matches(LIST)) continue;

      const list = change.target;
      const opener = list.previousElementSibling;
      if (!(opener instanceof HTMLElement) || !opener.matches(OPENER)) continue;

      markOpener(opener);

      const active = target.activeElement;
      const lost = active === null || active === target.body || list.contains(active);

      if (list === focused && !shows(list) && lost) {
        focused = null;
        opener.focus();
      }
    }
  });

  observer.observe(target.documentElement, {
    subtree: true,
    attributes: true,
    attributeFilter: ["style", "class", "hidden"],
  });
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

// A radio button of the list of a choice filter.
const CHOICE_OF_LIST = '[data-key="filter_select_dropdown_class"] input[type="radio"]';

/**
 * Keeps the list of a choice filter open while a person moves through it
 * with the keyboard. An arrow key on a radio button chooses the next one,
 * and the browser sends a click for that. Cinder closes the list on the
 * click of a choice, so the list would close under the focus at each
 * press. A click that a key made has no count of presses (`detail` is 0):
 * this stops such a click before LiveView sees it. The change of the
 * choice still goes to the server.
 */
export function holdOpen(target: Document = document): void {
  target.addEventListener(
    "click",
    (event: MouseEvent) => {
      if (event.detail !== 0) return;
      if (!(event.target instanceof Element) || !event.target.matches(CHOICE_OF_LIST)) return;

      event.stopPropagation();
    },
    true,
  );
}

// The button of the open list that the Escape key is for: the button that
// has the focus, or the button of the list that has the focus inside.
function openerToClose(from: Element): HTMLElement | null {
  const opener = from.matches(OPENER) ? from : from.closest(LIST)?.previousElementSibling;
  if (!(opener instanceof HTMLElement) || !opener.matches(OPENER)) return null;

  const list = listOf(opener);
  return list && shows(list) ? opener : null;
}

/**
 * Presses a sort control with Enter or Space, as a button does, and closes
 * an open list with Escape, which gives the focus back to its button.
 */
export function listen(target: Document = document): void {
  target.addEventListener("keydown", (event: KeyboardEvent) => {
    if (event.key === "Escape" && event.target instanceof Element) {
      const opener = openerToClose(event.target);
      if (!opener) return;

      // The press closes the list in the way of Cinder.
      event.preventDefault();
      opener.click();
      opener.focus();
      return;
    }

    // Enter on a choice of a list closes the list. The choice is made
    // already: the arrow keys chose it.
    if (event.key === "Enter" && event.target instanceof Element && event.target.matches(CHOICE_OF_LIST)) {
      const opener = openerToClose(event.target);
      if (!opener) return;

      event.preventDefault();
      opener.click();
      opener.focus();
      return;
    }

    if (event.key !== "Enter" && event.key !== " ") return;
    if (!(event.target instanceof HTMLElement) || !event.target.matches(CONTROL)) return;

    // Space would scroll the page.
    event.preventDefault();
    event.target.click();
  });
}
