# ADR 0076: Reports as PDF, with AshTypst

Status: accepted (the maintainer asked on 28 November 2026 to "design and
make some export to pdf reports with ashtypst", with the design first, as
an issue: the design is issue 7). It builds on ADR 0020 (rate limits),
ADR 0024 (grants), ADR 0041 (files) and ADR 0055 (photos), and adds to
ADR 0044 (the Nix package).

## Context

A refuge needs paper. A vet, another refuge or an adopter gets the record
of an animal. A card hangs on the door of a pen. An inspector asks for the
register of the animals. A volunteer walks through the sheds with the
tasks of the day, or counts the stock.

Rescord had pages for each of these facts, and the export of ADR 0054,
which is CSV for a spreadsheet. It had no document for paper. A page that
a browser prints has no page numbers, breaks a table in the wrong place,
and looks different in each browser.

AshTypst (`ash_typst`) renders Typst documents from Ash. Typst is a
typesetting system: one compiler, in Rust, that writes a PDF in
milliseconds. AshTypst carries it as a native library and needs no other
program on the server.

## Decision

- **A report is a generic action of `Rescord.Reports.Report`** that
  returns an `AshTypst.Document` with the bytes of a PDF. The domain
  `Rescord.Reports` has a function for each: `resident_record`,
  `cage_card`, `register`, `movements`, `task_sheet`, `stock`, `housing`.
  So a page, a job and the assistant (ADR 0069) make a report in the same
  way, and the policy of the action decides who may.
- **Seven reports, each for a need that paper has:**
  1. *The record of a resident*: its facts, identifiers, stay, family and
     groups, newest measurements, and the part of the journal that the
     person chooses (the medical history, all of it, or none), with its
     photos on request (24 at most, as thumbnails). It names no member,
     because it can leave the refuge.
  2. *The cage card*: one page on its side, with large type, the picture,
     where the resident lives, and the routines that name it.
  3. *The register*: each resident in care on a day, with its facts, its
     place and the identifiers that it has. The column of the identifiers
     is there only when a resident of the register has one.
  4. *Arrivals and departures*: a period, with each resident that came or
     went, the totals by kind and by species, and the numbers in care at
     the start and at the end.
  5. *The tasks of a day*: each task with a box to tick, and the late
     ones.
  6. *Stock*: what needs somebody first, then each item with its lots and
     a column for a count.
  7. *Housing*: each location with who lives there, for a walk through
     the refuge.
- **A report reads as the person who asks.** `Rescord.Reports.Render`
  runs each action in three steps:
  1. *The facts.* A module below `Rescord.Reports.Facts` reads the records
     through the other domains, with the actor and the organisation of the
     request. It never passes `authorize?: false`, so a report holds what
     the person reads on the pages, and nothing else.
  2. *The words.* The words of Rescord are in the web layer
     (`RescordWeb.ResidentWords` and the modules like it), and the core
     may not name the web layer (ADR 0009). So the configuration names
     the module that words the reports (`config :rescord,
     :report_wording`), as it names the modules of the grants. That module,
     `RescordWeb.ReportWords`, turns the facts into text that is ready to
     show.
  3. *The document.* The template gets the text as one value of Typst
     code, `d`, in a virtual file, and the photos as virtual files.
- **The `render` actions of AshTypst are not used.** One of them gives a
  template the records of one read of one resource. A report reads several
  domains and carries pictures. Rescord uses the rest of AshTypst: the
  templates of the resource, which are checked when the code compiles, the
  pool of compilers, the encoder of the data, and the document type.
- **No text of a record becomes markup.** The data goes in as strings of
  Typst code, which `AshTypst.Code` escapes, and a template shows a string
  as text. A name such as `#panic("no")` is that text on the page. A
  template reads no file outside `priv/typst`, and the pool clears the
  virtual files of a request before the next one.
- **`Rescord.Reports.Report` has no table.** `use Rescord.Resource` takes
  `table?: false` for a resource with actions only: no data layer, no
  history and no archive. The resource keeps the tenancy and the policy.
- **Each role can make each report**, with no new power. The grants give
  the seven actions to each role, as they give the reads: a report shows
  what the role reads anyway. A person makes at most 30 reports in a
  minute, in one count for all the reports.
- **The register follows the dates that the members gave.** A resident is
  in the register of a day when its arrival is on or before that day and
  it has no departure on or before it. The report of the arrivals and the
  departures uses the same rule, so the number at the start, plus the
  arrivals, minus the departures, is the number at the end. The facts of a
  resident are those of now. For a past day, its place and whether it was
  away are what the records held at the end of that day (ADR 0012).
- **The look is one file**, `priv/typst/look.typ`: A4, the typeface of the
  pages (Atkinson Hyperlegible, as OpenType files in `priv/typst/fonts`),
  the name of the organisation, a title, and a foot with the time of the
  request and "Page n of m". A render ignores the fonts of the server, so
  each server writes the same document. A character that the typeface does
  not have falls back to a typeface that Typst carries.
- **The documents are tagged PDF 1.7, and not PDF/A.** Typst refuses to
  write PDF/A when a character has no glyph, such as an emoji in a note,
  and a report that fails for one character is worse than one that is not
  an archive format.
- **A download is a `GET`** to `RescordWeb.ReportController`, from a
  plain link or a plain form, so it works with no script. The browser
  shows the PDF and keeps no copy. The page `/o/<short name>/reports`,
  which the site menu names, has the forms. The page of a resident has its
  record and its cage card, and the pages of the residents, the tasks, the
  inventory and the housing each link to their report.
- **The Nix package takes the native library as the other two** (MDEx and
  mjml): `nix/package.nix` fetches the build that AshTypst publishes, by
  its hash, and puts it where the compile looks. The Docker image and the
  tarball download it when they build.

## Consequences

- A new report is a module of facts, a module of words, a template, an
  action with its grant, and a route. `AGENTS.md` has the steps.
- The release is larger by the Typst compiler, about 73 MB on disk.
- A render runs in the process of its request, for some tens of
  milliseconds. The pool keeps the compilers between requests, one for
  each scheduler at most, and the rate limit bounds the work that one
  person can ask for.
- The words of a report are not in the core, so a caller with no web
  layer gets the same words. A second wording, for another language, is
  another module behind the same key.
- A report of a past day mixes two clocks on purpose: who was in care
  follows the dates of the events, and the place follows the records. A
  member who writes an arrival late changes the register of that day, as
  an inspector expects.

## Not decided here

- Paper other than A4, and a logo of the organisation on a report.
- A report by email, or made by a job on a schedule.
- Reports of adoptions and of money: they wait for those records.
