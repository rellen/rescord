# ADR 0100: The files of a transfer go in a job

Status: accepted. The design is issue 16, and the maintainer chose each of
its open points on 28 November 2026: 10 tries, "Send again" or "Withdraw"
for a transfer whose files did not arrive, the page hears the change
(ADR 0096) with no timer, the lifeline of Oban stays at 2 hours, and the
migration of the shared table has a line in the upgrade notes. The
assessment of Reactor, AshWorkflow and the signals of Ash
(`rescord-hull`, `docs/reviews/reactor-and-signals.md`) chose a signal
with a job of AshOban over a workflow for this. It changes ADR 0042 (the
states of a transfer) and ADR 0057 (when the files are copied), and uses
ADR 0067 (signals) and ADR 0091 (the file check).

## Context

A transfer to a partner on this server copied each photo and each PDF of
the copy in the action `send`, inside its transaction (ADR 0057). Each
file was read from the store of the refuge that sent it, and put under the
key of the transfer in the store of the refuge that receives it. For a
resident with a few photos that took a second. For a resident with
hundreds of photos and an S3 store far away it held a database connection
and the request of the page for minutes, and a fault of the store at file
200 rolled the whole send back, with the 199 files that were put left in
the store as leftovers.

## Decision 1: the send writes the copy, and a job copies the files

`send` writes the transfer with the state `sending`, the sources of its
files (the id in the copy and the key in the store of the sender) in
`sources`, and their number in `files_total`. It copies no file. It emits
`:transfer_started` of `Rescord.Transfers.Signals`, and
`Rescord.Transfers.Transfer` listens with the delivery
`AshOban.Signals`, so Oban writes the job in the transaction of the send
and runs it after the commit. A transfer whose copy names no file is
`sent` at once, and emits nothing: `Changes.StartCopy` emits only for a
transfer that is `sending`, with `emit ... dynamic?: true`. The `where:`
of a declarative `emit` cannot decide this, because Ash evaluates it
before the hooks of the change that sets the state.

The job runs the generic action `copy_files`
(`Rescord.Transfers.Actions.CopyFiles`). It has no transaction. It copies
the sources one at a time, from the first one that is not copied yet, and
writes how many are there (`progress`, in `files_copied`) at most once
each 2 seconds. Each write tells the pages of both refuges to read again
(ADR 0096), so a copy of many small files does not make them read for
each file. After the last file it runs `deliver`: the transfer is `sent`,
its sources are gone, and the refuge that receives it sees it.

The queue `transfers` runs two jobs at one time, so a large transfer
cannot take the queue of the emails.

## Decision 2: a fault

- A source that the store of the sender does not have: the transfer is
  `failed` at once, with the failure `file_missing`. Another try cannot
  help. The page says so, and offers "Withdraw": the person sends the
  resident again, with a new copy.
- Any other fault of the store: the job writes the count and returns the
  error, so Oban tries again later, from the count. The tenth try that
  fails makes the transfer `failed`, with `store_refused`. Oban waits
  longer before each try, so 10 tries take about 20 minutes. The page
  offers "Send again", which sets the state back to `sending` and emits
  the signal again, and "Withdraw".
- The person withdraws a transfer that is `sending`: the next write of
  the job writes the count, sees that the transfer is no longer
  `sending`, and ends with no error. The count names each file that the
  job put, so the file check finds no leftover (ADR 0091).
- Any other error on the last try, such as a read of the database that
  fails, makes the transfer `failed` too, so no transfer stays `sending`
  with no job.

`deliver` and `fail` filter on the state `sending`, so a job never
changes the state of a transfer that a person withdrew. `progress`
filters on the sources, which `deliver` removes, and writes the larger
of the count that is there and its own, so the count never goes back. A
second job of the same transfer, such as the one that the lifeline
starts again for a copy longer than 2 hours, puts the same bytes under
the same keys, and the first one that ends wins.

The lifeline of Oban stays at 2 hours: a job that a stopped server left
`executing` runs again after that, from the count. Until then the page
shows the count where it stopped. When the server stopped during the
last try, Oban discards that job, and the transfer stays `sending`: the
person withdraws it and sends the resident again. Both are rare, and the
maintainer chose to keep 2 hours.

## Decision 3: states, and who sees what

    sending --deliver--> sent --accept---> accepted
       |                   |---decline--> declined
       |                   |---withdraw-> withdrawn
       |---fail-----> failed --send_again--> sending
       |---withdraw-> withdrawn     |---withdraw---> withdrawn

Only the refuge that sends a transfer sees it while it is `sending` or
`failed` (`Checks.MemberOf` was already so: the refuge that receives
reads a transfer that is `sent` or `accepted`). The list of the sent
transfers says "Sending" and "120 of 300 files", or "Not sent" and why.
The page hears each write (ADR 0096) and needs no timer.

No person runs `copy_files`, `progress`, `deliver` or `fail`: their policy
is `signal_in(Rescord.Transfers.Signals, :transfer_started)` alone, and
the nested writes of the job carry its signal path. `send_again` needs
the power `:transfers`, as `send` does.

The paper trail keeps a version for the send, for `deliver` or `fail`,
and for `send_again`, and none for each count (`ignore_actions
[:progress]`).

## Decision 4: the file check while a transfer sends

`Rescord.Transfers.Files.keys_of/1` names, for a transfer with sources,
the first `files_copied` of them: the rest are not in the store yet, and
are no missing file. A file put after the last write of the count is a
leftover until the next write, and a check in that second reports it
(exit 0). After `deliver`, and for a transfer from before this ADR or an
import, it names each file of the copy, as before.

## Migration

`20261128091339_transfer_files_in_a_job` adds four columns to the shared
table `transfers`: `sources`, `files_total`, `files_copied` and `failure`.
It changes no row: each transfer that is there keeps its state, has no
sources, and counts 0 files. The states are text, so the two new ones
need no column. The previous release does not know the states `sending`
and `failed`, so the upgrade notes say to withdraw each such transfer
before going back.

## Consequences

- A send returns at once, whatever the number of files, and holds no
  connection while the files are copied.
- A fault of the store in the middle no longer rolls back the send, and
  the next try copies only what is left.
- The sender reads a copy while it is `sending` or `failed`, with no link
  to its photos and files, as some of them are not there yet.
- An export to a partner on another server (ADR 0043) is unchanged: it
  reads the files into one archive in its request.
