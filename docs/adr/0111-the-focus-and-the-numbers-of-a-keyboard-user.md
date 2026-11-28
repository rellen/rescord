# ADR 0111: The focus and the numbers of a person who uses the keyboard

Status: accepted. An assessment of the keyboard navigation and the data
entry (28 November 2026, in a real browser with the keyboard only) found
these faults. They are bugs of what ADR 0090 and ADR 0061 meant to do, so
this ADR fixes them without a new feature. The other findings of that
assessment wait for a choice of the maintainer.

## Context

- **Done on the wrong task.** ADR 0090 says that the rows of a Cinder
  collection have an `id`. They do not: Cinder writes `data-item-id` on a
  row, and no `id`. A task of an earlier day that is still open is in the
  list of today, and leaves it when it is done. LiveView then keeps the
  element of the row and puts the next task in it. `focus.ts` found the
  old row by its element, gave the focus to its first button, and a second
  Enter acted on the other task.
- **The focus fell to the page.** `focus.ts` counted an element as in the
  page when it had a box. An element inside a closed `<details>` and an
  element with `visibility: hidden` have one, but take no focus. So after
  a measurement, a journal entry or a movement of stock (each form is in a
  `<details>` that a reload closes), and after the button Clear of a
  filter, the focus went to the page and not to a place near. A link that
  LiveView moved, such as "The day after" on the tasks, lost the focus
  while it was still in the page, and `focus.ts` took that for a press
  beside the controls.
- **"1,2" became 12.** A field of `type="number"` drops a comma that a
  person types, with no word, and an arrow key changes the number. A
  weight of 1,2 kg was 12 kg.
- **The skip link** moved the reading place, but `document.activeElement`
  stayed the page, because `<main>` takes no focus.
- **The menu of a phone** is a popover. The Tab key left it open over the
  page, so it hid the control that had the focus (WCAG 2.4.11).

## Decision

- `focus.ts` names a part of the page by its `id`, or a row by its
  `data-item-id`. A part that LiveView reused for another thing, and each
  part inside it, is no place for the focus. When the row of the focus
  shows another record, the focus leaves it even when the page still has
  the focus. When the record is no longer in the collection, the focus
  goes to the heading of the collection (the heading that names its
  section, ADR 0087), and not to the row that took its place.
- An element is in the page when it has a box and `checkVisibility` (with
  `visibilityProperty`) says that it shows. A browser without
  `checkVisibility` counts the box only, as before.
- Only a press of a pointer just before a loss of the focus makes
  `focus.ts` forget its place. A loss with no press is a change of the
  page, and `restore` puts the focus back, also on the same element.
- `<.input type="decimal">` is a number with a part: a text field with
  `inputmode="decimal"`, no `step`, `min` or `max`, and no autocomplete.
  The value of a measurement and each quantity of the stock use it. The
  action checks the limits, as it did. A whole number keeps
  `type="number"`. A value with a comma is refused, with the problem of
  the form, and is never a different number.
- `<main>` has `tabindex="-1"`, so the skip link gives it the focus. It
  shows no ring: it is no control.
- `menu.ts` closes an open popover when the focus goes to a control
  outside it and its button.

### Forms that start where the work is

The maintainer chose these on 28 November 2026, with the bugs above.

- `forms.ts`: a form in a `<details>` that a person opens from its
  summary gives the focus to its first field. Ctrl or Cmd with Enter in a
  text area sends its form.
- A field with `autofocus` on a live page takes the focus in place of the
  `h1` (`focusHeading` in `focus.ts`). Only a form that a person goes on
  with has one: the measurement after a measurement.
- After a measurement, the page goes to `?again=<kind id>`: the form is
  open with that kind and its unit, and the value has the focus. A run of
  weights is the value and Enter for each.
- `?new=<kind>` opens the form of the journal with any kind of entry.
- The new task form is above the list of the day, not below its rows.
- A choice of how a resident came puts today in an empty date of the
  arrival.
- In the form of stock that came in, the quantity and the place come
  right after the lot, and the fields of a new lot after them.
- The list of the expenses of one resident records a new expense of that
  resident.

## Consequences

- The browser test of ADR 0090 holds the row that leaves and the menu of
  a phone. It failed on the old `focus.ts`.
- A value such as "1,2" is refused, not read as 1.2. A page could read a
  comma as the decimal mark of the locale of the organisation (ADR 0075);
  that is not done here.
- A Cinder collection in the layout of a list has no record on its items,
  so a reused item is not found. No list has a button that a press
  removes today.
