# ADR 0042: Transfers between partner refuges

Status: accepted (the answers are from the maintainer, 18 November 2026).
ADR 0100 adds the states `sending` and `failed`, while a job copies the
files of a transfer to a partner on this server.

## Context

A refuge sends a resident to another refuge. The maintainer answered:

- A refuge transfers to a partner. An administrator asks another refuge by
  its short name, and the two are partners when an administrator there
  accepts. No member sees a list of the other refuges.
- The receiving refuge must accept a transfer. Nothing appears there until
  a person with that power accepts it, and it can decline it.
- The copy is a snapshot at the transfer, and it does not change.
- An administrator records and accepts a transfer, and each member reads
  the copy.
- The copy holds the facts and the medical history always. The first
  refuge adds the other journal entries, the stay, the placements, or the
  families and the groups. An administrator gives the default parts as a
  setting, and the sender changes them for each transfer.

## Decision

- **A new domain, `Rescord.Transfers`**, with two resources outside the
  schemas of the organisations: `Partnership` and `Transfer`. A record
  between two organisations belongs to neither schema.
- **A new power, `:transfers`**, which ADR 0040's roles tick. It asks,
  answers and ends a partnership, and sends, answers and withdraws a
  transfer. A tenant migration gives it to the role with the key
  `:administrator` in each schema.
- **The policies read the role of the actor in one of the two
  organisations**: `Rescord.Transfers.Checks.PowerIn` with `side: :from`,
  `:to` or `:either`. The request has no tenant, so
  `Rescord.Accounts.Checks.Granted` cannot find the role.
- **The read is a filter** (`Rescord.Transfers.Checks.MemberOf`): each
  member reads the partnerships of their refuges; a transfer that their
  refuge sent; a transfer that it received and accepted; and, with the
  power, a transfer that waits for its answer.
- **The copy is plain data** (`Rescord.Transfers.Snapshot`), with text
  keys, labels for the values of the lists, and ISO 8601 text for dates and
  instants. `SendTransfer` builds it after the policy, as the actor, in the
  schema of the sender, and the copy names no id of the sender. The page
  that shows it (`RescordWeb.TransferWords`) reads that data, and no record
  of the sender.
- **A short name that no refuge has and the short name of the refuge that
  asks get one answer**, so the answer says no more than what the person
  typed.
- **The default parts** are the attribute `transfer_parts` of the
  organisation, which the power `:settings` changes.

## Consequences

- A transfer changes nothing at the refuge that sends it. That refuge
  records the departure of the resident itself.
- The refuge that receives reads a copy and has no resident record from
  it. A later step can register a resident from a copy.
- The filter of the read lists the organisations of the actor, one query
  for each organisation (`Rescord.Accounts.organisations_for/1`).
- A person reads the names of the two refuges of a partnership or a
  transfer, though only a root user reads an organisation through its
  actions: the domain loads the two with no policy, after the read.
- An administrator of one refuge can try short names to learn which
  exist. The answer for a refuge that exists and does not answer is a
  question that waits, which the other refuge can decline.
