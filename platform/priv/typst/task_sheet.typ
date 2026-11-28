// The tasks of one day (ADR 0076), each with a box to tick. The data is the
// value `d` that `RescordWeb.ReportWords.TaskSheet` words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame)

// The rows of a list of tasks.
#let sheet(rows) = records(
  (7mm, 1.5fr, 2.6fr, 1.4fr, 1.5fr, 1.5fr),
  ("", "Time", "Task", "For", "Who", "Done by, at"),
  rows.map(row => (
    tick-box(done: row.done),
    row.time,
    {
      text(weight: "bold", row.title)
      if row.kind != none {
        text(fill: muted, " · " + row.kind)
      }
      if row.note != none {
        linebreak()
        row.note
      }
    },
    or-dash(row.at("for")),
    row.who,
    if row.state != none { row.state },
  )),
)

#if d.late.len() > 0 [
  == Late
  #sheet(d.late)
]

== Today
#if d.tasks.len() == 0 {
  nothing("No task is due on this day.")
} else {
  sheet(d.tasks)
}
