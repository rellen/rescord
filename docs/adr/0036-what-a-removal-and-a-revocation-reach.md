# ADR 0036: What a removal and a revocation reach

Status: accepted

## Context

A review of the code on 16 November 2026 found four places where a change
to one record left another record, or an open page, behind:

- A LiveView reads the user when it connects and keeps it. A sign-out, the
  end of the root grant of a user, and a new role of a member did not reach
  a page that was open. A root user who lost the grant kept it on each open
  page, because the policy reads `root?` from the actor that the page holds.
- An administrator who removed a resident left it in its groups, its
  families and its links to parents and young ones. Each page that names a
  member of a group, or a relative, then read a resident that is not there,
  and stopped.
- A closed location kept the placements in it. The resident page then had a
  home with no location, and stopped.
- A journal entry could follow an entry of another resident, and a dose
  could name a prescription of another resident.

## Decision

- **A session names the sockets of its user** (`:live_socket_id`).
  `RescordWeb.UserAuth.disconnect/1` closes each open page of a user. A
  sign-out calls it, and so does each page that changes the root grant or
  the role of a person. Each page connects again, reads the user as the
  user is now, and sends away a person with no session.
- **The removal of a resident ends its ties** in the same transaction:
  each group, each family, and each link to a parent or a young one.
  `Rescord.Residents.Changes.EndTies` does this. The placement of the
  resident belongs to the locations, which depend on the residents. The
  housing leaves out a placement of a resident that it cannot read.
- **A location that holds a resident, a group or another location does not
  close.** The administrator moves them first.
- **An entry names records of its own resident**: an addendum follows an
  entry of the same resident, and a dose names a prescription of the same
  resident.
- Each new rule that reads the data runs after the policy
  (`before_action?: true`), so a person who cannot run the action gets the
  answer of the policy.

## Consequences

- A disconnect reaches each device of the user, and each one connects again.
  A person who signs out on one device sees each other page of theirs
  connect again for a moment.
- A removed resident keeps its placement row. The placement is history, and
  no page shows it.
- A task, a routine and a journal entry of a removed resident stay. A task
  names no subject for it.
