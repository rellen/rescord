# Rescord on a phone

This file is the assessment of 27 November 2026 of each page of Rescord at
the width of a phone, the list of what it found, and what was done about
each point. ADR 0061 holds the decisions. Read it first.

## How the pages were assessed

- A real Chromium, with the screen of a phone: 360 by 780 CSS pixels with
  touch, then 320 pixels, which is the least width that WCAG 1.4.10 asks
  for. Then 768 and 1280 pixels, to see that a wide screen did not get
  worse.
- The light and the dark scheme.
- An organisation with data: 42 residents, one with a name of 34 letters,
  an administrator with an email address of 61 letters, a group, housing of
  two levels, tasks, a routine, items with lots, a supplier, journal
  entries and five photos.
- Each flow was done on the phone screen, with taps: a new location, a
  group, a supplier, an item, stock that came in, a task, a routine, an
  identifier, a parent, a family, a placement, a journal entry, photos with
  a profile picture.
- Each page was measured by a script: the width of the page against the
  width of the screen, each box that scrolls sideways, the height and the
  width of each thing that a finger presses, and the size of the text of
  each control. Each page was also read in a screenshot.

The pages: the first page, the sign-in pages, the first page of an
organisation, tasks, routines, residents, a resident, the form of a
resident, the journal, the photos, the timeline, groups, a group, housing,
a location, inventory, an item, suppliers, lists, members, roles, partner
refuges, transfers, settings, export, and the root pages. The tools and the
dose calculator came later (ADR 0072), and `PhoneTest` visits them too. The
expenses, the form of an expense and the page of an expense came with
ADR 0082, and `PhoneTest` visits them too. `RescordWeb.PagesFixtures` now
makes the organisation and names the pages, for `PhoneTest` and for the
accessibility test of ADR 0090.

## What was found, and what was done

Each point below is fixed unless it says otherwise.

### The site menu

1. **The menu took five lines of a phone**, about 225 of 780 pixels, at the
   top of each page. It is now one bar with the button Menu, which opens
   the menu as a sheet below the bar. The menu is a popover of HTML, with
   no script.
2. **On a wide screen the menu wrapped** when the address of the person or
   the name of the organisation was long. From 60rem the menu has two rows
   by design: the name of the site and the account, then the parts of the
   organisation. A long address ends in an ellipsis.
3. **The menu did not say which part the page is in.** The stylesheet had
   the rule, and no page set `aria-current`. Each page now names its part.
4. **A long page had the menu only at its top.** The page of a resident is
   more than three screens long. The bar now stays at the top of a phone.
   On a phone on its side it scrolls with the page, because the screen is
   low.
5. **A link of the menu was 31px high.** It is 44px.

### Tables

6. **Each table was wider than the phone**: tasks, routines, residents,
   members, groups, items, lots, the history of an item, suppliers, partner
   refuges and transfers. The table scrolled sideways in its card. The
   buttons of a task were in the last column, out of view. A narrow column
   broke a name to one word a line. Below 40rem each row is now a card,
   with the first cell as its title and the name of the column before each
   other value.
7. **Nothing said that a table scrolled sideways.** No table does now.
8. **The sort of a table of Cinder is in its header.** The header of such
   a table stays on a phone, as a line of the sort controls.
9. **The title of a task had no header cell.** It is now the header cell
   of its row, so a screen reader names the task for each cell of the row.

### What a finger presses

10. **A button was 37px high, a select 38px, a field 41px.** Each is 44px
    or more.
11. **A summary was 23px high**, and only its words took a press. It is
    44px, and as wide as its box.
12. **The label of a box was 23px high.** It is 44px, and the whole line
    takes the press.
13. **The link "Photos" of a resident was a line of words beside a
    button.** It is a button like the one beside it.
14. **The links of the first page of an organisation were a list of words
    18px high.** They are cards.
15. **A link that is the title of a row or of a card was 20px high.** What
    takes the press is now larger than the words. The link of a breadcrumb
    and of an album is 44px high.
16. **Two buttons one above the other touched**: the values of a list with
    their buttons, the two buttons below the journal of a resident. A list
    of things with a button is now rows with a rule between them, the
    button at the end of the row. Buttons in a paragraph have a margin.
17. **The button that closes a flash message was 24px.** It is 44px.

### Text and forms

18. **The text of each control was 15px.** Safari on a phone makes the
    page larger when such a control gets the focus. It is 16px. The body is
    16px on a phone too.
19. **A long email address ran out of its box**, in the list of the members
    who do a task. A long word now breaks.
20. **The page of the transfers was wider than the phone**, by the file
    control of the import form. A form is now never wider than its place.
21. **The button of a form was small, at the left.** On a phone it is as
    wide as the form.
22. **No field of a number said which keyboard fits it.** A control of
    the type `number` now has an `inputmode`: the digits alone for a whole
    number, and the digits with a decimal mark for a quantity.
23. **The keyboard of a phone made the first letter of a short name a
    capital.** The two fields of a short name ask for none.

### Layout

24. **The photos were one column**, each card more than 500px high. They
    are two columns. The card with an open form takes both columns.
25. **A data list put each title above its value**: nine facts of a
    resident took 540px. A title and its value are side by side.
26. **A flash message covered the bar and the menu.** On a phone it is at
    the foot of the screen.
27. **A state with long words ran out of a narrow data list.** It breaks
    there.
28. **A hover stayed on a row or a button after a touch.** A hover is now
    for a pointer that can hover.

## What was looked at and is right

- No page has a dialog of its own. Three buttons of the photos ask with
  the dialog of the browser (`data-confirm`), which a phone draws itself.
- The viewport meta is `width=device-width, initial-scale=1`. Nothing
  stops a person from making the page larger.
- The filters of a table of Cinder are one column on a phone, and the
  choices of a filter are 44px high.
- The timeline, the journal entries and the housing cards fit a phone.
- The date, the time and the file controls use what the phone has for
  them.

## What is not done

- **Nobody looked with Safari on a phone, or with Firefox.** The tools of
  the assessment had Chromium alone. Look there at: the menu (the popover),
  the focus of a field (the page must not get larger), the date and time
  fields, and the file control of the photos, which should offer the
  camera.
  Look also at the charts of the measurements (ADR 0080): the line is in
  a nested `<svg>` that stretches, with `vector-effect:
  non-scaling-stroke`.
- **The address bar of the browser has no colour of Rescord.** That takes
  a `theme-color` meta, which would write a colour outside `tokens.css`
  (ADR 0015).
- **The routines, the roles, the partner refuges, the transfers and the
  export are not in the site menu.** They are one step away, on the first
  page of the organisation and on the pages that they belong to. The row
  of a wide screen has no room for them.
- **A long form is one long page**: the form of a resident, and the open
  forms of an item. Nothing is lost, and it takes a long scroll.
