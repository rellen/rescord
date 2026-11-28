// The look of each report of Rescord (ADR 0076): the page, the type, and
// the parts that the templates share. A template starts with
//
//   #import "look.typ": *
//   #import "data.typ": d
//   #show: report.with(d.frame)
//
// `data.typ` is a virtual file that `Rescord.Reports.Render` writes for each
// request. Each value in it is data: text, numbers, lists and dictionaries.
// A template never evaluates a text of `d` as markup.

// The colours of the design direction Scrubs (ADR 0015), for paper: the
// light scheme of `assets/css/layers/tokens.css`.
#let ink = rgb("#12211d")
#let muted = rgb("#47615a")
#let accent = rgb("#0a6a5c")
#let edge = rgb("#b5c9c2")
#let wash = rgb("#edf5f2")
#let alert = rgb("#b1222b")

// The page of a report, with the name of the organisation and of the report
// at the top of each page after the first, and the time and the page number
// at the bottom. `frame` is the dictionary `d.frame`. The paper is
// `frame.paper`, `a4` or `us-letter` (ADR 0093), and `flipped` turns it on
// its side. A template has one layout for both papers: it gives a width as
// a fraction of the page, or as a size that fits the smaller side of each.
//
// `title: false` leaves the title out of the first page, for a template that
// writes its own, such as the cage card.
#let report(
  frame,
  flipped: false,
  margin: (x: 16mm, top: 22mm, bottom: 20mm),
  title: true,
  body,
) = {
  set document(
    title: frame.title + ", " + frame.organisation,
    author: frame.organisation,
    date: frame.date,
  )
  set page(
    paper: frame.paper,
    flipped: flipped,
    margin: margin,
    header: context {
      if counter(page).get().first() > 1 {
        set text(size: 8.5pt, fill: muted)
        grid(
          columns: (1fr, auto),
          column-gutter: 8mm,
          frame.organisation, frame.title,
        )
        v(-2mm)
        line(length: 100%, stroke: 0.5pt + edge)
      }
    },
    footer: context {
      set text(size: 8.5pt, fill: muted)
      line(length: 100%, stroke: 0.5pt + edge)
      v(-2mm)
      grid(
        columns: (1fr, auto),
        column-gutter: 8mm,
        [#frame.made, by Rescord],
        [Page #counter(page).display() of #counter(page).final().first()],
      )
    },
  )
  set text(font: ("Atkinson Hyperlegible", "Libertinus Serif"), size: 10pt, fill: ink, lang: "en")
  set par(leading: 0.62em, spacing: 0.9em)
  show heading.where(level: 1): it => block(below: 2mm, text(size: 20pt, weight: "bold", it.body))
  show heading.where(level: 2): it => block(
    above: 7mm,
    below: 3mm,
    width: 100%,
    inset: (bottom: 1.5mm),
    stroke: (bottom: 0.75pt + accent),
    text(size: 12.5pt, weight: "bold", fill: accent, it.body),
  )
  show heading.where(level: 3): it => block(
    above: 5mm,
    below: 2mm,
    text(size: 10.5pt, weight: "bold", it.body),
  )

  if title {
    text(size: 9.5pt, fill: muted, weight: "bold", upper(frame.organisation))
    v(-2mm)
    heading(level: 1, frame.title)
    if frame.subtitle != none {
      text(size: 11pt, fill: muted, frame.subtitle)
    }
    v(2mm)
  }
  body
}

// A state: a word in a shape, never a colour alone.
#let state(word, kind: "none") = box(
  inset: (x: 2.2mm, y: 1mm),
  radius: 3mm,
  stroke: 0.75pt + if kind == "alert" { alert } else { muted },
  text(size: 8.5pt, weight: "bold", fill: if kind == "alert" { alert } else { ink }, word),
)

// Words for a part with nothing in it.
#let nothing(words) = text(fill: muted, style: "italic", words)

// A list of a label and a value: `rows` is a list of `(label:, value:)`.
#let facts(rows, label-width: 34mm) = grid(
  columns: (label-width, 1fr),
  row-gutter: 2.4mm,
  column-gutter: 3mm,
  ..rows.map(row => (text(fill: muted, row.label), row.value)).flatten(),
)

// A row of numbers, each above its label: `items` is a list of
// `(label:, value:)`.
#let counts(items) = {
  set par(spacing: 0.3em)
  grid(
    columns: items.len(),
    column-gutter: 3mm,
    ..items.map(item => box(
      inset: (x: 3.5mm, y: 2.5mm),
      radius: 1.5mm,
      fill: wash,
      [
        #text(size: 16pt, weight: "bold", item.value) \
        #text(size: 8.5pt, fill: muted, item.label)
      ],
    )),
  )
}

// A table of records. `columns` are the widths, `head` the words of the
// header, which each page repeats, and `rows` a list of lists of cells.
// `aligns` is the side of each column, such as `(left, right)`, for a table
// with a column of numbers.
#let records(columns, head, rows, size: 9pt, aligns: auto) = {
  set text(size: size)
  table(
    columns: columns,
    align: aligns,
    stroke: (x, y) => (bottom: 0.5pt + edge),
    inset: (x: 1.8mm, y: 2mm),
    fill: (x, y) => if y == 0 { wash },
    table.header(..head.map(word => text(weight: "bold", word))),
    ..rows.flatten(),
  )
}

// A value, or a dash for none.
#let or-dash(value) = if value == none { text(fill: muted, "–") } else { value }

// A box to tick.
#let tick-box(done: false) = box(
  width: 4mm,
  height: 4mm,
  stroke: 0.75pt + ink,
  radius: 0.6mm,
  baseline: 0.6mm,
  if done { align(center + horizon, text(size: 9pt, weight: "bold", "✓")) },
)
