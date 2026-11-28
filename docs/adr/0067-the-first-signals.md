# ADR 0067: The first signals: the removal of a resident, and the email of an invitation

Status: accepted (the maintainer chose proposals S1 and S3 of ADR 0062 on
28 November 2026). It adds to ADR 0036 (what a removal reaches), to
ADR 0032 and ADR 0033 (the tasks and the routines), and to ADR 0010 (Oban).
It changes how ADR 0022 sent the email of an invitation. Changed on
28 November 2026: a task that named only the removed resident is skipped.
The first text said that it stays due, and the maintainer chose otherwise.
Added on the same day: the departure of a resident, proposal S2 of
ADR 0062, which the maintainer chose to be "the same as a removal".

## Context

ADR 0062 found two gaps that an Ash signal is for.

- **A removed resident stayed in three other places.** ADR 0036 made the
  removal of a resident end its ties inside `Rescord.Residents`. The
  placement of the resident, the tasks that named it and the routines that
  named it kept it. Those records are in `Rescord.Locations` and
  `Rescord.Tasks`. Those two domains depend on the residents, so the
  residents cannot call them.
- **The email of an invitation was sent one time.** The change `Invite`
  sent it in a hook after the transaction. A fault of the mail server went
  to the log, and nothing sent the email again. The person who was invited
  heard nothing.

## Decision

### Where a signal module is

A signal module is in the domain that emits it, with the name
`Rescord.<Domain>.Signals`. When another domain listens, the domain that
emits exports the module (ADR 0066). The domain that listens already has
the emitter in its `deps`, because it depends on it. The emitter names no
listener: that is the point of a signal.

### The removal of a resident

`Rescord.Residents.Signals` declares `:resident_removed`, with the id of
the resident. `Resident.remove` emits it. `EndTies` stays for the ties
inside the residents.

| Listener | What it does |
| --- | --- |
| `Rescord.Locations.Placement` | Finishes the placement of the resident, with the action `:finish` that a person uses. |
| `Rescord.Tasks.TaskSubject` | Archives each subject that names the resident, with the new action `:drop`. Then it skips a task that is due and has no subject left. |
| `Rescord.Tasks.Routine` | Takes the resident out of `resident_ids` of each routine that names it, with the new action `:forget_resident`. |

- The listeners run **in the transaction of the removal**, and at the same
  `as_of`. A fault in a listener undoes the removal. A removal with a date
  ends the placement as of that date.
- **A task with another subject stays due.** A task that named the removed
  resident and another resident, a group or a location keeps the others.
- **A task that named only the removed resident is skipped**, when it is
  due. The maintainer chose this on 28 November 2026, in place of a task
  that stays due with no subject, which somebody must clear by hand.
  - The change `SkipTaskLeftAlone` of `:drop` runs the action
    `:skip_left_alone` of `Task`, in the transaction of the removal. No
    role has a grant for that action.
  - The reason is the text "The resident was removed". The person who
    removed the resident is the person who finished the task.
  - `skipped` is a state that a task has already, so there is no
    migration, and a member can open the task again. It is then due, with
    no subject.
  - A task that is done or skipped stays as it is. A task that another
    member finishes at the same moment stays as that member left it.
  - The skip does not make the next tasks of a routine, as the skip of a
    person does (ADR 0039): the routine loses the resident in the same
    removal, and the job of each hour makes its tasks.
- **A routine goes on** for its other residents, or for none. A routine
  that named only the removed resident makes its next tasks with no
  subject. The maintainer has not decided whether such a routine should
  pause.
- `TaskSubject` now archives (ADR 0012). It had no destroy action before,
  and a row that is deleted would break the key of its versions. A
  migration of each organisation adds the column `archived_at`.
- The journal, the photos, the inventory and the transfers do not listen.
  They hold the history of the resident, which stays.

### The departure of a resident

The maintainer chose on 28 November 2026 that a departure ends what a
removal ends. `Rescord.Residents.Signals` declares `:resident_departed`,
with the id of the resident, and `Departure.record` emits it.

| Listener | What it does |
| --- | --- |
| `Rescord.Locations.Placement` | Finishes the placement of the resident, with `:finish`. |
| `Rescord.Tasks.TaskSubject` | Archives each subject that names the resident in a task that is due, with the action `:drop_departed`. Then it skips a task that is due and has no subject left, with the reason "The resident left". |
| `Rescord.Tasks.Routine` | Takes the resident out of each routine, with `:forget_resident`. |

- **A task that is done or skipped keeps the resident.** A resident that
  left was a real resident, and those tasks are its history. A removal
  takes the resident out of each task, because the resident was a mistake.
- **A withdrawal restores nothing.** A member who withdraws a departure
  places the resident again and adds it to its routines again. A listener
  does not undo itself, and Rescord does not know which of the records the
  member wants back.
- **The listeners run at the instant of the action**, and not at the date
  of the departure. A departure of last week ends the placement now.
- A correction of a departure sends no signal.
- A departure that was recorded before this change ended nothing. Rescord
  does not go back to those residents.
- The person who records a departure needs the power `residents`, and no
  power for the housing or for the tasks.

### The email of an invitation

`Rescord.Accounts.Signals` declares `:member_invited`, with the address
and the address of the person who invites. The two invite actions of
`Member` emit it. `Member` listens with the generic action
`:send_invitation`, in a job:

```elixir
signals_in do
  from Rescord.Accounts.Signals do
    on :member_invited, :send_invitation,
      delivery: {AshOban.Signals, queue: :default, max_attempts: 16}
  end
end
```

- `AshOban.Signals` writes the job **in the transaction of the
  invitation**. The job is there only when the member is. Oban runs it
  after the commit.
- A fault of the mail server returns an error, and Oban runs the job
  again. Oban waits `15 + 2^n` seconds after try `n`, so 16 tries take
  about 18 hours. After the last try Oban discards the job. The invitation
  stands in each case: the person can ask for a sign-in link with no email.
- The change `Invite` now only finds or makes the user. The email is the
  same as before.
- The job holds the two addresses in its arguments, in the table of Oban.
  The pruner of Oban deletes a job one day after it ends. The log names the
  kind of a fault and never an address.
- The request for a sign-in link stays as it is (ADR 0019): its answer must
  not depend on the address, and a link that arrives hours later is of no
  use.

### The rules for a signal

1. **`:ash_signals` is a compiler**, after `:boundary` in `mix.exs`. It
   finds the listeners of each signal one time, at the build, and writes
   the modules `Ash.Signals.*`. They are in the application file, so a
   release loads them. `config/dev.exs` puts `:ash_signals` first in
   `reloadable_compilers`, so that a server that runs finds a new listener.
2. **One line of configuration lets a temporal resource emit.** The change
   that `emit` adds does not say that it is temporal safe (Ash 3.38.1), and
   Ash refuses it on a temporal resource. `config/config.exs` names it in
   `:temporal_safe_modules`. The change only reads the record and runs the
   listeners through Ash. Take the line out when Ash declares the change
   temporal safe.
3. **A listener action needs a policy line.** A listener runs with the
   actor of the action that emits, and that person often has no grant for
   the action of the listener. The policy of the listener says
   `authorize_if signal_in(Module, :signal)` before the check `Granted`:
   the action that emits was the decision. An action that only a listener
   runs has no grant in any role, so a person cannot run it, an
   administrator included. A root user passes the bypass, as for each
   action.
4. **A missing policy line is silent for a bulk listener.** `Granted` is a
   filter check. A listener that updates or destroys records runs a bulk
   action, and a filter that refuses updates nothing and returns no error.
   So the test of a listener uses a role that has the grant of the emitter
   and no other, and looks at the records afterwards.
   `Rescord.SignalsTest` does this.
5. **Inline or in a job.** A listener that must hold with the action that
   emits runs inline, which is the default. Work that reaches outside the
   database, such as an email, runs in a job with `AshOban.Signals`. A job
   runs with no actor (there is no actor persister) and with the tenant of
   the emitter, and the `signal_in` line lets it pass.
6. **A listener action of a public resource takes the signal as a
   `:struct`**, with `constraints: [instance_of: TheSignal]`, and not with
   the struct as the type. `ash_boundary` exports each type that a public
   resource names, and `boundary` does not know a struct that a signal
   module generates (ADR 0066).
7. **An update or a destroy listener whose change is not atomic needs a
   read action with `pagination keyset?: true, required?: false`**, named
   as `read_action`. Ash reads the records in pages. Without it the listener
   fails with `NoMatchingBulkStrategy`.

## Consequences

- An administrator who removes a resident leaves no placement, no task
  subject and no routine that names it. The person needs the power
  `remove_residents` and no power for the housing or for the tasks.
- An invitation whose email met a mail server that was down arrives when
  the server is back, within about 18 hours.
- An invitation returns before the email is sent. A page cannot say that
  the email failed. It could not before either: the fault went to the log.
- A test that reads the email of an invitation runs the jobs first, with
  `Rescord.AccountsFixtures.send_invitations/0`. Oban runs no job by itself
  in a test.
- A new listener on a resource that the policy sweep holds (ADR 0063) is
  closed to each person until a grant says otherwise. The sweep passes with
  the listener actions of this ADR.
- The fault of rule 2 is worth a report to the Ash project.
