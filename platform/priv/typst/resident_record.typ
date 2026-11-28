// The record of one resident (ADR 0076). The data is the value `d` that
// `RescordWeb.ReportWords.ResidentRecord` words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame)

#grid(
  columns: if d.photo != none { (1fr, 52mm) } else { (1fr,) },
  column-gutter: 8mm,
  [
    #state(d.status)
    #v(1mm)
    #facts(d.about)
  ],
  ..if d.photo != none {
    (
      align(right, box(
        clip: true,
        radius: 2mm,
        image(d.photo, width: 52mm, alt: "The profile picture of " + d.name),
      )),
    )
  },
)

#if d.identifiers.len() > 0 [
  == Identifiers
  #facts(d.identifiers.map(row => (label: row.kind, value: row.value)))
]

#if d.stay.len() > 0 [
  == Stay
  #facts(d.stay)
]

#if d.relations.len() > 0 [
  == Family and groups
  #facts(d.relations)
]

#if d.measurements.len() > 0 [
  == Newest measurements
  #facts(d.measurements.map(row => (label: row.date, value: row.words)))
]

#if d.journal != none [
  == #d.journal.title
  #if d.journal.entries.len() == 0 {
    nothing(d.journal.empty)
  }
  #for entry in d.journal.entries {
    block(
      breakable: false,
      width: 100%,
      below: 3.5mm,
      inset: (left: 3mm, y: 0.5mm),
      stroke: (left: 1.5pt + edge),
      {
        text(weight: "bold", entry.kind)
        h(2mm)
        text(size: 9pt, fill: muted, entry.date)
        set par(spacing: 0.55em)
        if entry.follows != none {
          parbreak()
          text(size: 9pt, fill: muted, entry.follows)
        }
        if entry.facts != none {
          parbreak()
          entry.facts
        }
        if entry.note != none {
          parbreak()
          entry.note
        }
        if entry.files != none {
          parbreak()
          text(size: 9pt, fill: muted, entry.files)
        }
      },
    )
  }
]

#if d.photos.len() > 0 [
  == Photos
  #grid(
    columns: (1fr, 1fr, 1fr),
    column-gutter: 5mm,
    row-gutter: 6mm,
    ..d.photos.map(photo => block(breakable: false, {
      box(clip: true, radius: 1.5mm, image(
        photo.file,
        width: 100%,
        height: 42mm,
        fit: "cover",
        alt: if photo.caption != none { photo.caption } else { "A photo of " + d.name },
      ))
      set par(spacing: 0.4em)
      set text(size: 9pt)
      if photo.caption != none {
        photo.caption
        linebreak()
      }
      text(fill: muted, photo.date)
    })),
  )
  #if d.more_photos != none {
    v(2mm)
    nothing(d.more_photos)
  }
]
