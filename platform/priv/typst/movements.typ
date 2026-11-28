// The arrivals and the departures of a period (ADR 0076). The data is the
// value `d` that `RescordWeb.ReportWords.Movements` words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame)

#counts(d.summary)

// The totals of one side: by kind and by species, next to each other.
#let totals(by-kind, by-species) = grid(
  columns: (1fr, 1fr),
  column-gutter: 10mm,
  [
    === By kind
    #facts(by-kind, label-width: 62mm)
  ],
  [
    === By species
    #facts(by-species, label-width: 62mm)
  ],
)

== Arrivals
#if d.arrivals.len() == 0 {
  nothing("No resident arrived in these days.")
} else {
  totals(d.arrivals_by_kind, d.arrivals_by_species)
  v(2mm)
  records(
    (1.4fr, 1.1fr, 1fr, 1.5fr, 1.8fr),
    ("Date", "Name", "Species", "How it came", "Note"),
    d.arrivals.map(row => (
      row.date,
      text(weight: "bold", row.name),
      row.species,
      row.kind,
      or-dash(row.note),
    )),
  )
}

== Departures
#if d.departures.len() == 0 {
  nothing("No resident left in these days.")
} else {
  totals(d.departures_by_kind, d.departures_by_species)
  v(2mm)
  records(
    (1.4fr, 1.1fr, 1fr, 1.5fr, 0.8fr, 1.4fr),
    ("Date", "Name", "Species", "How it left", "In care", "Note"),
    d.departures.map(row => (
      row.date,
      text(weight: "bold", row.name),
      row.species,
      row.kind,
      or-dash(row.stay),
      or-dash(row.note),
    )),
  )
}
