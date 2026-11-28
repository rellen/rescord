// The expenses of a period (ADR 0082): the sums, what the organisation
// owes to each member, and the list. The data is the value `d` that
// `RescordWeb.ReportWords.Expenses` words. Each amount is text that is
// ready to show: the template adds nothing. `d.tax` is the name of the tax
// of the organisation, such as GST, or none: then no table has its column
// (ADR 0089).
#import "look.typ": *
#import "data.typ": d
#show: report.with(d.frame, flipped: true)

#text(fill: muted, d.scope)
#v(1mm)
#counts(d.summary)

// A table of sums: a label, how many expenses, and their amount. With the
// name of a tax, it has the tax in each amount too.
#let sums(head, rows, tax: none) = if tax == none {
  records(
    (2fr, 0.8fr, 1.4fr),
    (head, "Expenses", "Amount"),
    rows.map(row => (row.label, row.count, row.amount)),
    aligns: (left, right, right),
  )
} else {
  records(
    (2fr, 0.8fr, 1.4fr, 1.2fr),
    (head, "Expenses", "Amount", tax + " in it"),
    rows.map(row => (row.label, row.count, row.amount, row.tax)),
    aligns: (left, right, right, right),
  )
}

#if d.expenses.len() > 0 {
  grid(
    columns: (1fr, 1fr),
    column-gutter: 10mm,
    [
      == By state
      #sums("State", d.by_state, tax: d.tax)
    ],
    [
      == Approved or paid back, by category
      #if d.by_category.len() == 0 {
        nothing("No expense of these days is approved or paid back.")
      } else {
        sums("Category", d.by_category, tax: d.tax)
      }
    ],
  )
}

== To pay back
#if d.owed.len() == 0 {
  nothing("The organisation owes nothing to a member now.")
} else [
  #text(fill: muted)[What the organisation owes to each member now. An expense here can have a payment before these days.]
  #v(1mm)
  #block(width: 60%, sums("Member", d.owed))
]

== The expenses
#if d.expenses.len() == 0 {
  nothing("No expense has a payment in these days.")
} else if d.tax == none {
  records(
    (0.5fr, 1.6fr, 2.2fr, 1.5fr, 1.1fr, 1fr, 1.8fr, 1.2fr, 0.8fr, 1.1fr),
    ("No.", "Date", "What", "Paid to", "Category", "Resident", "Paid by", "State", "Receipts", "Amount"),
    d.expenses.map(row => (
      row.number,
      row.date,
      text(weight: "bold", row.description),
      or-dash(row.payee),
      or-dash(row.category),
      or-dash(row.resident),
      row.paid_by,
      row.state,
      row.receipts,
      row.amount,
    )),
    size: 8.5pt,
    aligns: (left, left, left, left, left, left, left, left, right, right),
  )
} else {
  records(
    (0.5fr, 1.5fr, 2.1fr, 1.4fr, 1.1fr, 1fr, 1.7fr, 1.1fr, 0.8fr, 1.1fr, 1fr),
    ("No.", "Date", "What", "Paid to", "Category", "Resident", "Paid by", "State", "Receipts", "Amount", d.tax + " in it"),
    d.expenses.map(row => (
      row.number,
      row.date,
      text(weight: "bold", row.description),
      or-dash(row.payee),
      or-dash(row.category),
      or-dash(row.resident),
      row.paid_by,
      row.state,
      row.receipts,
      row.amount,
      or-dash(row.tax),
    )),
    size: 8.5pt,
    aligns: (left, left, left, left, left, left, left, left, right, right, right),
  )
}
