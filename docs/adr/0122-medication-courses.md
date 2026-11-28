# ADR 0122: Medication courses on a time line

Status: accepted. The sixth chart that is built of issue 36 (its chart
6), which the maintainer chose to build with the other nine on
28 November 2026 (ADR 0116).

## Context

A refuge asks who is on what now, and whether the doses were given. A
prescription entry has a medication, a dose and a route in words, and
maybe its first and last days. A dose entry can name its prescription, and
a task of a routine can be for a prescription. Issue 36 proposes a time
line of the courses of three weeks around today, with a tick for each dose
given, a ring for each dose due and not given, and a line at now.

## Decision

1. **A course is a prescription** that runs on a day of the window:
   `Rescord.Journal.courses/3`. It starts on its first day, or on the day
   of its entry when it names none. A course with no last day goes on
   while its resident is in care or away, so an old prescription with no
   end does not run for ever. The doses given are the dose entries that
   name it, in the window.
2. **A dose missed** is a task of the prescription, due in the window,
   that was skipped or is overdue: `Rescord.Tasks.missed_doses/4`. The
   web layer joins the two, because Tasks already depends on Journal
   (a done task writes its dose). A dose entry and its task are not
   linked, so a ring and a tick are not matched: a task skipped and then
   given by hand shows both.
3. **The page** is `RescordWeb.MedicationInsightsLive` at
   `/o/:organisation/insights/medication`: the two weeks before today and
   the week after, a row for each course in the order of the names of the
   residents. Its link, "Meloxicam for Biscuit", opens the prescription in
   the journal. Its note says the dose, the route, the days, and the doses
   given and missed. Each member can open it.
4. **`timeline/1` gains marks and now.** A row can have `marks`: a tick
   for a dose given and a ring for a dose missed, in `--text`, shapes and
   no colour of a state. `now` draws a dotted line in each row.
   `Chart.instant_x/3` places a local instant on a scale of days.

## Consequences

- A prescription with no routine has no task, so it shows ticks and never
  a ring.
- The frequency of a prescription is words, so the page cannot say how
  many doses were due: only the tasks say that.
