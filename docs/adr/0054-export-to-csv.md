# ADR 0054: Export of the data as CSV

Status: accepted (the maintainer, 25 November 2026).

## Context

A rescue could not take its data out of Rescord: for a vet, for an
inspection, or to move to another system. The only export was the transfer
file of one resident (ADR 0043).

The maintainer chose the scope, the power and the shape: the whole data of
the organisation, a new power, and one ZIP of CSV files as of a chosen date.

## Decision

- **`Rescord.Export`** writes one ZIP: a CSV file for each table, and
  `README.txt`, which says when, what each file holds, which files keep no
  history, and which file each `_id` column names.
- **The tables are the resources of the domains**: the lists, the residents,
  the locations, the journal, the tasks and the inventory, with the shared
  base lists, the organisation, its roles and its members, each in a file
  that has the name of its table. A column is a public attribute; a member
  also has its email. `Rescord.Export.excluded/0` names each resource that
  is left out, with the reason: the users and their tokens, and the
  transfers, which belong to two refuges and hold keys. A test holds each
  resource of the domains of the configuration to one of the two lists, so a
  new resource is in the export, or someone writes why not.
- **A date, today at first.** A temporal resource is read as it stood at
  the end of that day in the time zone of the organisation, or now for
  today. A resource with no history (a task, a routine, a member, a role, an
  attachment) is as it is now, and the README says so.
- **The power `export`**, which the role `administrator` has, and which an
  administrator can give to another role. It grants the generic action
  `:export` of `Rescord.Accounts.Organisation`, which only allows: the export
  runs it first, and then reads each table as the person, with the grants
  of their role.
- **CSV as RFC 4180 writes it**, in UTF-8 with a byte order mark for the
  spreadsheets, and a `'` before a text that a spreadsheet would run as a
  formula. No dependency: the ZIP is the `:zip` of Erlang.
- The photos and the PDFs of the journal are not in the ZIP;
  `journal_attachments.csv` lists them.

## Consequences

- `/o/<short name>/export` has the form, and `RescordWeb.ExportController`
  sends the ZIP, because a page of LiveView cannot send a file.
- The export is in memory. That is enough for the data of a refuge; a very
  large organisation would need a stream.
- The files are the tables, joined by their ids, which suits another system
  and a spreadsheet with a lookup more than a person who reads one file. A
  file for a person, such as one row for each resident with its names, can
  come later.
