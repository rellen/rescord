// Who lives where (ADR 0076): each location with its count, and the
// residents and the groups that live there. The data is the value `d` that
// `RescordWeb.ReportWords.Housing` words.
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame)

#text(size: 11pt, weight: "bold", d.total)
#v(2mm)

#if d.rows.len() == 0 {
  nothing("The refuge has no location.")
}

#for row in d.rows {
  block(
    breakable: false,
    width: 100%,
    below: 3mm,
    inset: (left: row.depth * 7mm + 3mm, y: 1mm),
    stroke: (left: (paint: edge, thickness: 1.5pt)),
    {
      grid(
        columns: (1fr, auto),
        column-gutter: 6mm,
        {
          text(size: if row.depth == 0 { 12pt } else { 10.5pt }, weight: "bold", row.name)
          if row.kind != none {
            text(fill: muted, "  " + row.kind)
          }
        },
        {
          text(weight: "bold", row.count)
          if row.over {
            h(2mm)
            state("Over its capacity", kind: "alert")
          }
        },
      )
      set par(spacing: 0.5em)
      for name in row.residents {
        parbreak()
        tick-box()
        h(2mm)
        name
      }
      for group in row.groups {
        parbreak()
        text(fill: muted, "Group: " + group.name)
        for name in group.members {
          parbreak()
          tick-box()
          h(2mm)
          name
        }
      }
    },
  )
}

#if d.unplaced.len() > 0 [
  == With no place
  #for name in d.unplaced [
    #tick-box() #h(2mm) #name \
  ]
]
