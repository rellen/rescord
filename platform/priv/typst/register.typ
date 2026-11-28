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
  // The column of the identifiers is there only when a resident of the
  // register has one: many species carry no microchip and no tag.
  let identifiers(cell) = if d.with_identifiers { (cell,) } else { () }
  let columns = (
    (("Name", 1.1fr), ("Species", 0.9fr), ("Breed", 1fr), ("Sex", 0.9fr), ("Born", 1.5fr))
      + identifiers(("Identifiers", 1.5fr))
      + (("Arrival", 1.4fr), ("Place", 1.3fr), ("Status", 0.8fr))
  )
  records(
    columns.map(column => column.at(1)),
    columns.map(column => column.at(0)),
    d.rows.map(row => (
      (text(weight: "bold", row.name), or-dash(row.species), or-dash(row.breed), row.sex, or-dash(row.born))
        + identifiers(if row.identifiers.len() == 0 { or-dash(none) } else { row.identifiers.join(linebreak()) })
        + (row.arrived, or-dash(row.place), row.status)
    )),
    size: 8.5pt,
  )
}
