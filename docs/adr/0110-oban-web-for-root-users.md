# ADR 0110: Oban Web for root users

Status: accepted. The maintainer agreed on 28 November 2026 to add Oban
Web, so that the person who runs a server can watch its jobs.

## Context

Rescord runs its background work in Oban (ADR 0010): the emails of the
invitations, the replies of the assistant (ADR 0069), the files of the
transfers (ADR 0100), the tasks of the routines and the other cron jobs.
An operator had no view of them: no list of the jobs that wait or failed,
and no way to retry one but IEx.

`oban_web` is open source (Apache 2.0). Version 2.13.2 needs `oban ~> 2.24`
(Rescord has 2.24.2) and brings `oban_met` 1.3.3, which gathers the counts
in memory and adds no table. Its reporter, on the leader node, counts the
jobs of each state and queue each second, and estimates a count above
50,000 with a function of the database that it makes itself while the
server runs (`CREATE OR REPLACE FUNCTION oban_count_estimate`), unless
`auto_migrate` is off.

`oban_dashboard/2` mounts a live session of its own, with its own root
layout, and three plain routes for its stylesheet, its script and its
font. Its resolver says who the user is and which actions they may take;
the page checks an action again on the server when its event arrives.

## Decision

1. **Mount it at `/root/oban`, for a root user alone.** It cannot be a page
   of the live session `:root`, so it is in a scope of its own, with three
   guards:
   - the new pipeline `:root`, with the plug
     `RescordWeb.UserAuth.require_root/2`, before each of its routes, its
     files too. Anyone else goes to `/`, as the hook sends them;
   - the hook `{RescordWeb.UserAuth, :require_root}`, which reads the
     session again each time the page connects;
   - `RescordWeb.ObanResolver`, which refuses anyone who is not a root user
     (`{:forbidden, "/"}`), so that a change to the router alone cannot
     open the page.
2. **A root user may cancel and retry a job, and pause and resume a
   queue. Nothing else.** Deleting a job loses the record of what happened.
   Inserting or editing a job runs work that no action of Rescord made,
   past its policies. Scaling or stopping a queue, and each change to a
   cron entry or a pruner rule, makes the server differ from its
   configuration. Each of those stays off.
3. **The resolver keeps the id of the user alone.** The page keeps its
   user in the session of the LiveView, which is signed and not encrypted.
4. **The root page links to it**, beside the notifications and the usage
   counts.
5. **Nothing changes for the content security policy.** Rescord sends the
   policy of `put_secure_browser_headers/2` (`base-uri 'self';
   frame-ancestors 'self'`), and Oban Web loads each file from this server,
   below `/root/oban`. Its layout takes nonces (`csp_nonce_assign_key`) for
   the day Rescord sends a stricter policy.
6. **The function of Oban Met comes from a migration.** Rescord turns
   `auto_migrate` of the reporter off, and the migration
   `20261128131500_add_the_count_estimate_of_oban_met` makes the function,
   with the SQL of `oban_met` 1.3.3 written out. So the schema changes
   only in a migration, with its upgrade note and the rehearsal of the
   start (ADR 0073, ADR 0081), and the user of the database needs no right
   to create a function while Rescord runs.

## Consequences

- An operator sees the arguments, the errors and the output of each job.
  An AshOban job holds ids, a tenant and the id of an actor; a job of Ruby
  holds ids and no word (ADR 0069). A new job that holds the words of a
  person must take this page into account, or give the resolver a
  `format_job_args/1` that hides them.
- Oban Web is not ours: it has its own look, its own menu and classes, and
  the accessibility test and the phone test do not visit it. The colophon
  says so. Its logo leads back to `/root`.
- `RescordWeb.ObanWebTest` holds the guards for a person who is signed out,
  a member and an administrator, the files, the hook alone, the actions of
  the resolver, and a cancel that works while a delete does nothing. The
  page needs an Oban that runs, and the tests run Oban in its testing mode,
  so a test that opens the page runs an instance of its own with the same
  name, with no queue and no plugin.
- Oban Met queries `oban_jobs` each second on one node, whether or not a
  root user has the page open. That is a small count on an indexed table.
- A new version of `oban_met` can change its function. Compare it with
  the migration at an update, and change it with a new migration.
- A new version of `oban_web` can add an action. The test lists each action
  of `Oban.Web.Resolver` that must stay off: read its list of actions at an
  update.
