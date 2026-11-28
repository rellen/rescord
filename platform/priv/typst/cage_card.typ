// The cage card of one resident (ADR 0076): one page on its side, with type
// that a person reads from the door of a pen. The data is the value `d`
// that `RescordWeb.ReportWords.CageCard` words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame, flipped: true, title: false, margin: (x: 14mm, top: 14mm, bottom: 18mm))

#grid(
  columns: (92mm, 1fr),
  column-gutter: 10mm,
  if d.photo != none {
    box(clip: true, radius: 3mm, image(
      d.photo,
      width: 92mm,
      height: 78mm,
      fit: "cover",
      alt: "The profile picture of " + d.name,
    ))
  } else {
    box(
      width: 92mm,
      height: 78mm,
      radius: 3mm,
      stroke: (paint: edge, thickness: 1pt, dash: "dashed"),
      align(center + horizon, nothing("No picture")),
    )
  },
  [
    #text(size: 9.5pt, fill: muted, weight: "bold", upper(d.frame.organisation))
    #v(-3mm)
    #heading(level: 1, text(size: 44pt, d.name))
    #v(1mm)
    #if d.species != none {
      text(size: 20pt, d.species)
      h(4mm)
    }
    #box(baseline: -1.5mm, state(d.status))
    #v(2mm)
    #set text(size: 13pt)
    #facts(d.about, label-width: 36mm)
    #if d.away != none {
      v(1mm)
      state(d.away, kind: "alert")
    }
  ],
)

#v(3mm)
#grid(
  columns: (92mm, 1fr),
  column-gutter: 10mm,
  [
    #if d.identifiers.len() > 0 [
      == Identifiers
      #set text(size: 12pt)
      #facts(d.identifiers.map(row => (label: row.kind, value: text(weight: "bold", row.value))), label-width: 30mm)
    ]
    #if d.measurements.len() > 0 [
      == Newest measurements
      #set text(size: 12pt)
      #for words in d.measurements [
        #words \
      ]
    ]
  ],
  [
    == Care
    #set text(size: 12.5pt)
    #if d.routines.len() == 0 {
      nothing("No routine names this resident.")
    }
    #for routine in d.routines {
      block(breakable: false, below: 4mm, {
        text(weight: "bold", routine.title)
        linebreak()
        routine.when
        if routine.note != none {
          linebreak()
          text(size: 11pt, fill: muted, routine.note)
        }
      })
    }
  ],
)
