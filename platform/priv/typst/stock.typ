// The stock of each item (ADR 0076): what needs somebody first, then each
// item with its lots, and a column for a count. The data is the value `d`
// that `RescordWeb.ReportWords.Stock` words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame)

== Needs somebody
#if d.attention.len() == 0 {
  nothing("Nothing: each item is in stock and in date.")
} else {
  records(
    (1.3fr, 1.3fr, 2.6fr),
    ("Item", "What", "Detail"),
    d.attention.map(row => (text(weight: "bold", row.item), row.words, row.detail)),
  )
}

#if d.categories.len() == 0 [
  == Items
  #nothing("The inventory has no item.")
]

#for category in d.categories [
  == #category.name
  #for item in category.items {
    block(breakable: false, width: 100%, below: 5mm, {
      grid(
        columns: (1fr, auto),
        column-gutter: 6mm,
        text(size: 11pt, weight: "bold", item.name),
        text(size: 11pt, weight: "bold", item.level),
      )
      v(-1.5mm)
      text(size: 9pt, fill: muted, {
        item.states
        if item.reorder != none {
          " · Reorder level: " + item.reorder
        }
      })
      if item.note != none {
        linebreak()
        text(size: 9pt, item.note)
      }
      if item.lots.len() > 0 {
        v(-1mm)
        records(
          (1.2fr, 1.5fr, 2.2fr, 0.9fr, 1fr),
          ("Lot", "Expiry", "Place", "Record", "Count"),
          item.lots.map(lot => {
            let places = if lot.places.len() == 0 {
              ((place: none, level: lot.level),)
            } else {
              lot.places
            }
            places
              .enumerate()
              .map(((index, place)) => (
                if index == 0 { lot.name },
                if index == 0 {
                  lot.expires
                  if lot.state != none {
                    linebreak()
                    text(weight: "bold", lot.state)
                  }
                },
                or-dash(place.place),
                place.level,
                [],
              ))
          }).flatten(),
          size: 8.5pt,
        )
      }
    })
  }
]
