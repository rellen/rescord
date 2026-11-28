// The register of the residents on a day (ADR 0076), on a page on its
// side. The data is the value `d` that `RescordWeb.ReportWords.Register`
// words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame, flipped: true)

#counts(d.counts)
#v(3mm)

#if d.rows.len() == 0 {
  nothing("The refuge had no resident in care on this day.")
} else {
  records(
    (1.1fr, 0.9fr, 1fr, 0.9fr, 1.5fr, 1.5fr, 1.4fr, 1.3fr, 0.8fr),
    ("Name", "Species", "Breed", "Sex", "Born", "Identifiers", "Arrival", "Place", "Status"),
    d.rows.map(row => (
      text(weight: "bold", row.name),
      or-dash(row.species),
      or-dash(row.breed),
      row.sex,
      or-dash(row.born),
      if row.identifiers.len() == 0 { or-dash(none) } else { row.identifiers.join(linebreak()) },
      row.arrived,
      or-dash(row.place),
      row.status,
    )),
    size: 8.5pt,
  )
}
