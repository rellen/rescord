# ADR 0108: Help on the pages, one name for one thing, and English ready for Gettext

Status: accepted (the maintainer, 28 November 2026, on two decision
cards: "English only, ready for later" and "Yes, glossary as written").

## Context

A review of each page on 28 November 2026 asked three questions: does a
page help the person who fills it in, is the help written plainly with
one name for one thing, and does Rescord use Gettext.

- **Help.** The way help is shown was right: `<.input hint=...>` writes
  a visible line under the field and ties it to the field with
  `aria-describedby`. There was little of it: 35 of 246 fields had a
  hint, and the tick box of `<.input>` dropped its hint, so the help
  beside a tick box was a loose `<small>` that a screen reader did not
  tie to the box. Most collections that are empty for a new organisation
  said what was missing, and not what to do. Words such as lot,
  placement, partner card, fingerprint, power, feed and ntfy were not
  explained where they show.
- **Tooltips.** Three `title` attributes held words that showed nowhere
  else: the whole email address in the menu, which CSS cut short, the
  public key of the push service, and a name the button already had. A
  `title` shows only on hover, so a person on a touch screen or with a
  keyboard never reads it (WCAG 1.4.13).
- **Names.** One thing often had two or three names: organisation,
  refuge and rescue for the organisation itself; member for a person and
  for a resident of a group; overdue, late and still due; location,
  place and where.
- **Gettext.** About 28 of roughly 2,100 strings that a person reads went
  through Gettext: the menu, the footer and the notices of the
  connection. The files `errors.pot` and `en/LC_MESSAGES/errors.po` were
  the stock files of Phoenix, with messages of Ecto that Rescord never
  writes, and each `msgstr` was empty. ADR 0075 says the pages are in
  English, and that a translation is not part of it.

## Decision

### The pages stay in English, ready for Gettext later

- **No move to Gettext now.** The calls of Gettext that are there stay.
  The stale `errors.pot` and `errors.po` go: they described no message
  of Rescord.
- **Text is written so that a later move is cheap:**
  - A sentence is whole. A page does not join a name to the end of a
    sentence that another module wrote, and does not change the case of
    words that another module gave.
  - A count with a word goes through `RescordWeb.Locale.count/3`, which
    takes the word for one and the word for more than one, whole: never
    an `s` added to a word, and never an `if` on `1` in a page.
  - A list of names that a person reads goes through
    `RescordWeb.Locale.list/1`, which has the pattern of the locale. The
    lists that join words by hand stay until their page changes.
- **The document names the language and region** of the organisation:
  `<html lang>` is the tag of `RescordWeb.Locale.current/0`, such as
  `en-AU`, and a page with no organisation has the default.
- **The calendar feed** has the forms of the organisation, as its pages
  do.

### Help on the pages

- **A field that a volunteer could get wrong has a hint**: what it
  takes, what an empty field means, and what follows from a choice. A
  label is short, and the condition or the default goes in the hint.
  A tick box takes a hint too.
- **A collection that a new organisation sees empty says what to do**:
  the sentence for nothing yet says what the thing is in a few words,
  and where to add one, or who can.
- **A word of Rescord is explained where it first shows** on a page,
  in a few words, or in a `<details>` when it takes more.
- **No words only in a `title`**, nor in anything that shows only on
  hover or focus. What a person needs to read is on the page.

### One name for one thing

AGENTS.md holds the glossary: the word to use, and the words not to use
for the same thing.

## Consequences

- A translation, when one comes, still needs each string moved to
  Gettext, the errors written as whole sentences, a language for each
  organisation or member, and a translator. The rules above keep that
  work from growing.
- The pages read the same words for the same thing, so a person who
  learns a word on one page knows it on the next.
- Page tests that held the old words change with them.
