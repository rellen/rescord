# ADR 0092: The journal of a resident is a collection

Status: accepted (the maintainer chose proposal M2 of ADR 0079 on
28 November 2026; the design is in issue 14).

## Context

The journal page read each entry of the resident and showed each one. A
resident with years of entries had a long page, and a member could not
find an entry by a word, a kind or a date (ADR 0079).

The page is more than a list. It has the form of a new entry, the forms
of each entry (a correction, an addendum, a dose to plan), the conditions
of the resident (ADR 0083), and three parameters of its own in the
address: `only`, `episode` and `kind`. Two other pages link to one entry
with `#entry-<id>`.

## Decision

1. **The entries are a collection of Cinder in the list layout**, the
   newest first, in pages of 25, 50 or 100, with the state in the address
   (ADR 0084). Each entry is the card that it was, with its forms.
   `Rescord.Journal.query_to_journal/2` gives the query, with the facts
   of each kind and the files of each entry.
2. **Filters and a search:**
   - `only`: "The medical history". The address `?only=medical` is the
     same as before. `Rescord.Journal.medical/1` narrows the query.
   - `kind`: the kind of the entry.
   - `happened_at`: the dates between which the thing happened.
   - The search finds a text in the note, in the name of a medication or
     of a vaccine, and in the dose of a prescription
     (`Rescord.Journal.with_text/2`).
3. **The page keeps three parameters of its own**, and Cinder keeps them
   when it changes the address:
   - `episode=<id>`: the entries about one condition, as before.
   - `entry=<id>`: one entry, with each entry that adds to it. A link from
     another page to one entry uses it, because that entry can be on a
     later page, and a `#entry-<id>` finds nothing there. The page says
     that it shows one entry, with a link to each entry.
   - `new=diagnosis`: opens the form of a new entry as a diagnosis. It was
     `kind=diagnosis`, and the filter on the kind has that name now. An
     old address with `kind=diagnosis` shows the diagnoses and opens no
     form.
4. **The page does not hold the entries.** An event that names an entry or
   a file by its id reads that record again, as the person, and only from
   the journal of this resident: `Rescord.Journal.entry_of/3` and
   `attachment_of/3`. Before, the page looked in the entries that it had
   in hand.
5. **The files of an entry are the relationship `attachments`**, in the
   order of their upload. `Rescord.Journal.attachments_of/2` stays for
   the photos, the report and the transfer, which read each entry.
6. **A link to another condition keeps the search and the filters.** The
   page gives the parameters of the address back in the link, and reads
   none of the parameters of Cinder.
7. **After a write the page opens again at the same address**, with its
   search, its filters and its page, as it did before with its own
   parameters.
8. `Rescord.Journal.prescriptions/2` reads the entries with a
   prescription, and not each entry.

## Consequences

- The page reads 25 entries, their facts and their files, and the
  prescriptions of the resident. Before, it read each entry two times.
- The two links in the header ("Show the medical history" and "Show each
  kind of entry") are gone: the filter does their work. The subtitle of
  the page no longer says "The medical history".
- The filter on the date reads a day as a day of UTC, as the stock history
  does (ADR 0084). An entry near midnight in the time zone of the
  organisation can be on the other side of the edge.
- On a phone the filters take most of the first screen. The entries
  follow them.
- A new entry that the filters leave out is not on the page after the
  write. The filters are in view, and say so.
- The events of the forms of a card reach the page: a form inside the
  component of Cinder has no target, so its event goes to the LiveView.
- A list item of Cinder that holds a card has no line below it
  (`vendor.css`).
- The timeline, the photos, the record of a resident and a transfer read
  the journal as before, with `Rescord.Journal.entries/2`.
- No migration, no new dependency and no new power. The relationship
  `attachments` adds no key to the database: an attachment is not
  temporal, and names its entry by a plain id.
