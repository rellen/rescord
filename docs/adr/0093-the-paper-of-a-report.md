# ADR 0093: A report is on A4 or on US Letter, and the organisation chooses which

Status: accepted (the maintainer, 28 November 2026: "let's support A4 and
letter now, default set in settings, default option in settings A4").
Issue 7 holds the design, in a comment.

## Context

ADR 0076 made each report on A4, and left other paper as not decided. A
rescue in the United States or in Canada prints on US Letter: a document
for A4 loses its foot there, or the printer makes it smaller. Rescord is
open source and a rescue that we do not know runs it, so the paper cannot
be a line of the configuration of one server.

## Decision

- **A report is on one of two papers: A4 and US Letter.**
  `Rescord.Accounts.paper_sizes/0` is the list, `[:a4, :us_letter]`. A
  third paper later is one more value there, a name in
  `RescordWeb.ReportWords`, and the name that Typst has for it.
- **The paper is a setting of the organisation** (ADR 0068): the attribute
  `paper_size` of `Rescord.Accounts.Organisation`, A4 at first. An
  administrator and a root user change it on the settings page, with the
  action `set_paper_size`, which is in the grants of the settings. Each
  member reads it. It is no variable of the environment.
- **The default is A4 for each organisation**, also for one whose language
  and region are `en-US`. The paper does not follow the locale: the
  maintainer chose A4, and one rule that does not depend on another
  setting is easier to say in the upgrade notes. The form that creates an
  organisation does not ask for the paper.
- **A person can choose the other paper for one document.** Each action of
  `Rescord.Reports.Report` takes the optional argument `paper`. With none,
  `Rescord.Reports.Render` takes the paper of the organisation. Each
  address of `RescordWeb.ReportController` takes `paper=a4` or
  `paper=us_letter`. A value that names no paper is the same as none, as
  for `journal`: an old link still gives a document.
- **Two pages have a control "Paper"**, with the paper of the organisation
  chosen at first. The page Reports has one at its top, for each form and
  each link of the page. The choice is in the address of the page, so the
  page still works with no script: the control is a form with `GET`. The
  section "On paper" of the page of a resident has one for the record and
  the cage card, and the cage card is a second button of that form
  (`formaction`). A link to a report on another page uses the paper of the
  organisation.
- **A template has one layout for both papers.** The paper goes to the
  template in the frame of the document, as `d.frame.paper`, and `report`
  of `look.typ` sets the page from it. A template says only whether the
  paper is on its side. The widths are fractions of the page, and the
  sizes in millimetres, such as the picture of the cage card, fit the
  smaller side of each paper. The margins are the same on both.

## Consequences

- One migration adds the column `paper_size` to the organisations, with
  the default `a4`. Each organisation that is there gets A4, which is what
  its reports had, so no report changes at the upgrade.
- A rescue that prints on US Letter changes one setting, one time.
- A new template is looked at on both papers, in portrait or on its side
  as it is. `Rescord.ReportsTest` holds the size of the pages of each
  report on both.
- US Letter on its side is 17.6 mm narrower than A4 on its side, and
  US Letter upright is 17.6 mm shorter than A4 upright. A report can thus
  have one page more on one paper than on the other.

## Not decided here

- Other papers, such as A5 for a cage card or US Legal.
- A paper for each report, or for each member.
- A logo of the organisation on a report (ADR 0076).
