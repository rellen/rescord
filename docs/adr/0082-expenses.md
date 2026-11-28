# ADR 0082: Expenses, with receipts, and money with AshMoney

Status: accepted. The maintainer asked on 28 November 2026 for expenses
that a member or the organisation paid, with receipts, with a CSV file and
a PDF, with AshMoney and AshLocalize, and said that Rescord is not an
accounting system. The design is issue 9 of the repository. It adds to
ADR 0012, ADR 0024, ADR 0036, ADR 0040, ADR 0041, ADR 0054, ADR 0063,
ADR 0068, ADR 0075 and ADR 0076.

## Context

A rescue pays for a vet, for food and for fuel. Often a member pays first,
and the rescue pays that member back. Rescord recorded the residents and
the supplies, and nothing about what they cost.

**Rescord is not an accounting system, and this record does not make it
one.** It has no ledger, no accounts, no bank feed, no invoices, no
payroll and no tax return. It records an expense, keeps its receipt, gets
a decision on it, and remembers that the member was paid back. Then it
gives the list to the system that does the accounts, as a CSV file, and to
a committee, as a PDF.

## Decision

### The record

- **A domain of its own**, `Rescord.Expenses`, with two resources in the
  schema of each organisation: `Expense` and `Receipt`.
- **An expense** has a number that counts up in the organisation (a
  `bigserial` of the table, so a person can write it on a bank transfer),
  who paid (`paid_by`: `member` or `organisation`, and `payer_id` when a
  member paid), the amount, the day of the payment (not after today in
  the time zone of the organisation), who was paid (text), what it was
  for, a category, the resident that it was for or none, a note, and the
  user who recorded it. The decision and the payment back have their own
  attributes.
- **A category is a value of a list of the organisation**, "Expense
  category", the sixteenth dimension of `Rescord.Lists` (ADR 0016).
- **An expense has a state machine**, so it is not temporal (ADR 0012).
  Its history is its paper trail, and the paper trail of its receipts.
  `Rescord.Expenses.history/2` reads both as one list of events.

  ```
  submitted --approve--> approved --reimburse--> reimbursed
  submitted --decline--> declined --revise--> submitted
  approved, declined, reimbursed --reopen--> submitted
  submitted, declined --withdraw--> (archived)
  ```

- **`reimburse` is only for an expense that a member paid.** A page shows
  the state `approved` of such an expense as "To pay back": the
  calculation `status` of the expense holds that, so a filter and a sort
  use it too.
- **An expense that the organisation paid, recorded by a person who can
  approve, is approved at once.** That person would only approve their
  own record a moment later.
- **Each action that changes the state filters on the state in the
  database**, as a task does (ADR 0032). Two people who decide at the same
  moment make one decision, and the second one reads how the expense is
  now.
- **A withdrawn expense is archived** with its receipts (ADR 0036). The
  files stay in the store.

### A receipt

- A receipt is a file of an expense: a photo or a PDF, 20 MB at most. A
  person adds 5 at one time at most. It follows the attachments of the
  journal (ADR 0041) and the photos (ADR 0055).
- **The check of a file is one module**, `Rescord.Storage.Upload`, that
  the journal and the expenses share. The type comes from the first bytes
  (JPEG, PNG, GIF, WebP or PDF). A photo goes through
  `Rescord.Images.prepare/1`: it loses its metadata, the GPS position with
  the rest, and gets a thumbnail. A PDF stays as it was sent.
- The keys are `<organisation id>/receipts/<id>` and
  `<organisation id>/thumbnails/<id>`.
- `RescordWeb.ReceiptController` sends a file that the person reads, in a
  sandbox, with no cache.
- A receipt is not necessary. The list shows how many each expense has.

### Money

- **`ash_money` 0.2.8** (MIT), with `ex_money` 6.3 and `ex_money_sql` 2.2
  (both Apache-2.0). `ex_money` 6 is built on Localize, the library of
  ADR 0075, so the locales and the money have one source of data.
- **AshLocalize is not used**, for the reason of ADR 0075: it has no
  release.
- **In PostgreSQL an amount is the composite type
  `money_with_currency`**, in the schema `public`, with its functions and
  operators. `AshMoney.AshPostgresExtension` in the list of the repo makes
  the migration that installs it. It is no PostgreSQL extension: the role
  of the migrations needs the right to make a type, functions, operators
  and aggregates in `public`, and no more. The tables of each organisation
  use the type of `public`.
- **Each organisation has a currency**: the attribute `currency`, an
  ISO 4217 code, `AUD` at first. An administrator changes it on the
  settings page, with the action `set_currency` under the power
  `settings` (ADR 0068).
- **The list of the currencies is `Rescord.Accounts.currencies/0`.** The
  data of Localize marks each code as legal tender, so the list leaves
  out, by name, the codes that are no money that a person pays with: the
  funds and the units of account (`BOV`, `CHE`, `CHW`, `CLF`, `COU`,
  `MXV`, `USN`, `UYI`, `UYW`), and each code that starts with `X` (metals,
  test codes, "no currency") but the currencies of a union (`XAF`, `XCD`,
  `XCG`, `XOF`, `XPF`).
- **A new expense is in the currency of the organisation.** No action
  takes a currency: the argument `amount` is a decimal, and
  `Changes.SetAmount` makes the money. An expense keeps its currency when
  the setting changes, and when a person changes its amount.
- **An amount is more than zero**, less than 100 million, and has no more
  decimal places than its currency has (2 for `AUD`, 0 for `JPY`).
- **Rescord converts no amount**, and the exchange rate service of
  `ex_money` does not start. A sum is always of one currency
  (`Rescord.Expenses.sum/1`): with two currencies the page shows two
  sums.
- **The amount is the whole amount, with its tax.** There is no field for
  GST or VAT.
- **A page writes an amount in the locale of the organisation**, with
  `RescordWeb.Locale.money/1`: `$1,234.50` for Australian dollars in
  English (Australia). A form takes a plain number. A CSV file has a plain
  number and the code.

### Who can do what

Two powers, in the area "Expenses" of the roles page (ADR 0024):

| Power | Grants | The roles that have it at first |
| --- | --- | --- |
| `expenses` | Record an expense. Change and withdraw their own while it waits or after it was declined. Add a receipt to an expense that they read, and remove a receipt that they added. | Administrator and member |
| `manage_expenses` | Read each expense. Record an expense that another member paid. Approve, decline, record the payment, open a decision again. Change each expense, and remove each receipt. | Administrator |

- **A member of the organisation reads their own expenses**: those that
  they recorded, and those that name them as the payer. That read needs no
  power, as the read of the members needs none. Only `manage_expenses`
  reads each expense. What a member spent and is owed is not for each
  other member.
- The policy of both resources is the usual one: a bypass for a root
  user, then `Rescord.Accounts.Checks.Granted`. `own` and
  `of_own_expense` are scopes of `Rescord.Expenses.Grants`. The sweep of
  the policies (ADR 0063) holds each new action.
- **No action takes the state, the author, the person who decided or the
  person who paid back as input.**
- **A validation that reads as the actor runs before the action**
  (`before_action?: true`), not in the changeset: the category, the
  resident, the payer, and the expense of a receipt. So the policy answers
  first, and a person with no grant gets "forbidden" and learns nothing
  about what exists.
- **One step of approval.** No limit by amount, and no second signature.
  A person can approve their own expense: a small rescue often has one
  treasurer, and the history says who decided.
- **No draft, and no email.** A recorded expense waits for a decision at
  once.
- Two migrations of the organisations give the powers to the roles with
  the keys `administrator` and `member` (ADR 0040). The order of
  `@power_keys` in `Rescord.Accounts.Grants` is the order in which the
  migrations add the powers.

### The pages

- `/o/<short name>/expenses`: three sums, then the list as a
  `Cinder.collection`, then the link to the CSV file. The filters are in
  the address (`Cinder.UrlSync`), so the link of the file carries them.
  For a person who manages: what waits for a decision, what is to pay
  back and to how many members, and what was spent this month. For each
  other person: the same for their own expenses.
- `/o/<short name>/expenses/new` and `/<id>/edit`: the form, with the
  receipts. "Who paid?" has a third answer, "Another member paid", for a
  person who manages.
- `/o/<short name>/expenses/<id>`: the amount and the state, the facts,
  the decision, the payment, the receipts, and what happened.
- The page of a resident links to its expenses, the settings page has
  "Currency", and the lists page has "Expense category".
- The web layer asks `Rescord.Expenses.can?/4` what a button can do, and
  `Rescord.Expenses.list_query/2` for the query of the list. It builds no
  query and names no resource (ADR 0009).

### The exports

- **CSV, from the list**: `/o/<short name>/expenses.csv` with the filters
  of the list, one row for each expense that the person reads, written
  with `Rescord.Export.CSV`. The amount is a plain number, with the code
  of its currency in the next column. It needs no power of its own: it
  holds what the page holds.
- **The export of the data** (ADR 0054) gets `expenses.csv`,
  `expense_receipts.csv` and `expense_categories.csv`. An amount of money
  is two columns in each file of the export: `<name>` and
  `<name>_currency`. The export reads as the person, so `expenses.csv`
  holds each expense only for a person who manages the expenses; the
  README says so. The files of the receipts are not in the ZIP.
- **PDF**: one more report of `Rescord.Reports` (ADR 0076), "Expenses".

## Not in this work

Income, donations and budgets. Mileage at a rate, and a daily allowance.
A split of one receipt. A payment through a bank. A supplier of the
inventory as the payee. A tool of the assistant. The cost of a resident
as a sum on its page. A row for the waiting expenses on the first page
(ADR 0065).

## Consequences

- The server gets one more need: the role of the migrations makes a type,
  functions, operators and aggregates in the schema `public`. The role
  that owns the database has that right.
- `ex_money` brings `ex_money_sql` and `localize_sql`. Nothing fetches an
  exchange rate.
- A new currency of ISO 4217 comes with a new release of Localize.
- A person who manages the expenses reads what each member spent. A role
  with `export` and without `manage_expenses` exports only its own
  expenses.
- A change of the currency of an organisation changes no expense. A list
  with two currencies has two sums, and no total.
- A new action of `Expense` or `Receipt` needs its grant in
  `Rescord.Expenses.Grants`, or the sweep of the policies fails.
