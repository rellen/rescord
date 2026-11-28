# ADR 0089: The tax in the amount of an expense

Status: accepted (the maintainer chose the field on 28 November 2026). It
changes one decision of ADR 0082, "The amount is the whole amount, with
its tax. There is no field for GST or VAT." The design is in issue 19. It
adds to ADR 0063, ADR 0068, ADR 0073 and ADR 0076.

## Context

In many countries the price on a receipt includes a tax on goods and
services: GST in Australia and New Zealand, VAT in the United Kingdom and
the European Union. An organisation that is registered for that tax claims
it back, so the person who does its accounts needs the tax of each
expense, apart from the amount.

ADR 0082 gave an expense one amount, with its tax in it. The person who
does the accounts then opens each receipt to read the tax. That is the
work that the list of the expenses was to save.

Rescord is not an accounting system (ADR 0082), and this record does not
make it one. A tax has rates, rules for what it applies to, and a return.
Rescord holds none of them.

## Decision

- **An expense can hold the tax that is in its amount**: the attribute
  `tax`, an `AshMoney.Types.Money` that it can be without. A person copies
  it from the receipt. The amount stays the whole amount, with the tax in
  it: Rescord never adds the tax to the amount, and never takes it off.
- **No tax is not a tax of zero.** An expense with no value says nothing
  about its tax: nobody recorded it. Zero says that the receipt shows no
  tax. Each expense that was there before this work has no value.
- **Rescord knows no rate and no tax code.** Nothing fills the field in,
  and nothing checks it against the amount but the rules of the next
  point. A receipt often holds goods with a tax and goods without one, so
  a rate would be wrong for it.
- **The tax is in the currency of the amount**, zero or more, not more
  than the amount, and with no more decimal places than the currency has.
  No action takes a currency: the argument `tax` is a decimal, and
  `Rescord.Expenses.Changes.SetTax` makes the money, as
  `Changes.SetAmount` does for the amount. A change that makes the amount
  less than the tax is refused.
- **An organisation names its tax, and with no name its expenses record
  no tax.** The attribute `tax_name` of the organisation is text of at
  most 12 characters on one line, such as `GST` or `VAT`, with no value at
  first. An administrator sets it on the settings page, with the action
  `set_tax_name` under the power `settings` (ADR 0068). It is a setting in
  the database, not a variable of the environment. The name is only a
  word: it is the label of the field, of the column and of the sum.
- **With no name, the field is on no form, and an action refuses a tax.**
  An organisation that takes the name away keeps the tax of each expense
  that has one. A change of such an expense keeps its tax, and a person
  can still take the tax off.
- **`submit`, `record` and `revise` take the tax**, with the rights that
  they have: the person of an expense gives the tax while the expense
  waits, or after a refusal.
- **`set_tax` corrects the tax in each state**, for the power
  `manage_expenses` (ADR 0063). It changes only the tax: the amount, the
  state and the decision stay. A person who manages the expenses thus
  corrects the tax of an approved expense, or of one that was paid back,
  with no need to open the decision again. The paper trail of the expense
  keeps each correction with who made it, and the history on the page
  says "corrected the tax in the amount".
- **The pages show the tax only where there is one.** The form has the
  field "GST in the amount (optional)", with the name of the organisation,
  after the amount. The page of an expense has the row when the expense
  has a tax, and the form of the correction for a person who manages,
  while the organisation names a tax.
- **The CSV file of the list always has the column `tax`**, after the
  amount and before the currency: a plain number, or an empty cell for an
  expense with none. The column is there with no name of a tax too, so the
  file has one shape for each organisation.
- **The export of the data** (ADR 0054) gets the two columns of an amount
  of money for it, `tax` and `tax_currency`, in `expenses.csv`.
- **The report of the expenses** (ADR 0076) has the tax when the
  organisation names one, or when an expense of the period has one: a
  box with the tax in the expenses that are approved or paid back, a
  column in the sums by state and by category, and a column in the list.
  With neither, the report is as before. With a tax and no name, the
  column has the word "Tax".
- **A sum of the tax is `Rescord.Expenses.tax_sum/1`**, one amount for
  each currency, as a sum of the amounts is. It counts only the expenses
  that have a tax.

## Not in this work

A rate that fills the tax in. Tax codes, such as "GST free" or "input
taxed". A tax of each line of a receipt. More than one tax on one
expense. A registration number of the organisation or of the payee. A
return, or a report in the form of one.

## Consequences

- Two migrations, each with its line in the upgrade notes (ADR 0073):
  one adds the name of the tax to the organisations, in the database, and
  one adds the tax to the expenses, in each organisation. Both add a
  column with no value, and change no row.
- An organisation that does not name a tax sees no change, but the new
  empty column `tax` in the CSV file. A tool that reads that file by the
  position of a column must change: the currency and each column after it
  moved one place.
- A tax that a person typed wrong is wrong in the sums too. Rescord
  cannot know. The person who manages the expenses reads the receipt, and
  corrects the tax.
- The sum of the tax is only of the expenses that have one. A report of
  an organisation that started to record the tax in the middle of a period
  has a sum that is less than the tax that it paid.
