# ADR 0083: The conditions of a resident are records, which a diagnosis starts

Status: accepted (the maintainer asked on 28 November 2026 if Rescord
tracks the conditions that residents have, temporary or chronic, "so we
can see trends or filter records/journals". The design is issue 11). It
builds on ADR 0030 (the journal), and adds to ADR 0035 (the timeline),
ADR 0042 (the copy of a transfer), ADR 0054 (the export) and ADR 0061
(mobile first).

## Context

Rescord had a list Condition in each organisation, and a journal entry of
the kind diagnosis that names one condition of that list. That is a point
in time. Rescord could not say what a resident has now, when a condition
started and when it was over, which entries are about it, who else has
it, or how often it comes.

## Decision

- **A condition of a resident is a record**, `Rescord.Journal.Episode`,
  in the table `episodes` of each organisation: one time that a resident
  has a condition, from its start to its end. It names the resident and a
  value of the list Condition, and holds the first day, the last day when
  it is over, a mark for a chronic condition, and a note of up to 200
  characters. It is a temporal resource with a paper trail. No day is
  after today in the time zone of the organisation (ADR 0026), and the
  last day is not before the first day.
- **The states are ongoing and resolved**, from the last day alone. A
  chronic condition shows as chronic while it is ongoing. Chronic is a
  mark of the condition of one resident, and not of the value of the
  list: one resident has a respiratory infection for two weeks, and
  another keeps it.
- **A diagnosis starts a condition, and nothing else does.** The journal
  entry of the kind diagnosis is the one way to say that a resident has a
  condition, so no second form says the same thing. No role has the
  action that starts an episode: `Rescord.Journal.Changes.LinkEpisode`
  runs it for a diagnosis, so the policy of the entry decides.
  - A diagnosis of a condition that the resident does not have now starts
    an episode, on the day of the entry or on the day that the member
    gives.
  - A diagnosis of a condition that the resident has now joins that
    episode. A resident and a condition have one ongoing episode at most.
  - A diagnosis after the condition was resolved starts a new episode. A
    condition that comes again is thus counted again.
- **A journal entry is about one condition, or none**: the column
  `episode_id` of `journal_entries`. An entry names only an episode of
  its own resident. A dose is about the condition of its prescription and
  an addendum about the condition of its entry, when the member names
  none. A correction changes it, or takes it off.
- **A correction of the condition of a diagnosis** gives the new
  condition to its episode when the diagnosis is the only one of that
  episode. In each other case the diagnosis moves, by the rules of a new
  diagnosis.
- **What a member does with a condition**: mark it as resolved, open it
  again, and change its days, the mark and the note, with the power
  `journal`; and remove one that was a mistake, with the power
  `correct_journal`. A removal takes the condition off its entries in the
  same transaction (ADR 0036): the entries stay in the journal.
- **No migration of the data.** A diagnosis from before has no episode,
  and the migration makes none: an episode needs to know if the condition
  is over, and the old entry does not say. A migration that guessed would
  show each old diagnosis as ongoing. Rescord asks a member in the pages
  (ADR 0065, ADR 0073): such a diagnosis has a button "Track this
  condition", which starts the episode on the day of the entry.
- **The pages** (ADR 0037, ADR 0061), each written for a phone first:
  - The page of a resident has a section Conditions: what the resident
    has now, and what it had in a closed part.
  - The journal of a resident has a link for each condition.
    `?episode=<id>` shows the entries about one condition, with the card
    of that condition and its actions. `?kind=diagnosis` opens the form
    of a diagnosis.
  - The timeline says when a condition was resolved and when it was
    opened again. Its start is its diagnosis.
  - `/o/<short name>/residents/conditions` is the page Conditions, in the
    part Residents. Each member can open it, and it reads as that member.
- **The counts** are two functions of `Rescord.Journal`.
  `conditions_now/1` counts the ongoing conditions of the residents that
  are in care or away, by condition and by the location where each
  resident lives now. `conditions_started/2` counts the conditions that
  started in each of the last months, for each condition or for one. The
  page also has each episode in a `Cinder.collection` with a search,
  filters and a sort.
- **A count is a number and a bar.** The bar is a small inline SVG that a
  screen reader does not read, in the one colour of the accent:
  `RescordWeb.ConditionComponents.counts/1`, with a section of
  `components.css`. It is not a chart component: the line charts of the
  measurements are a work of their own.
- **The copy of a transfer** has `"conditions"`, always, each by the name
  of its condition, and an entry of the copy says the condition that it
  is about under `"about"`. `Snapshot.clean/1` keeps a condition that has
  a name and a first day. **The export** has `episodes.csv`, and
  `journal_entries.csv` has the column `episode_id`.

## Consequences

- A rescue sees what its residents have now and how often a condition
  comes, and reads the journal of a resident one condition at a time.
- A rescue that upgrades sees no condition until a member records a
  diagnosis or tracks an old one. A diagnosis that nobody tracks is in no
  count.
- The count by location is about where the residents live now. Rescord
  does not keep where a resident lived on the first day of a condition.
- A server with an earlier version reads a copy with conditions as
  before: its `clean/1` drops the keys that it does not know. A copy from
  an earlier version has no part Conditions on its page.
- The assistant (ADR 0069) can get a read tool for the conditions later:
  the read action has a description. A diagnosis never has a proposal, so
  the assistant starts no condition.
- Not decided here: a code or a shared catalogue for a condition, a
  severity, a row on the first page for a condition that stays open for a
  long time (ADR 0065), and the conditions in a report (ADR 0076).
