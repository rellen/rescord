# ADR 0072: The tools of an organisation, and a dose calculator that shows its working

Status: accepted (the maintainer asked on 28 November 2026 for "a dosage
calculator tool", with "tools a new top level menu", and for the design
first, as an issue: the design is issue 6). It builds on ADR 0071 (units
of measure), and adds to ADR 0037 and ADR 0061.

## Context

A member who gives a medication often has three numbers: the weight of the
animal, the dose rate that the vet gave (so much for each kilogram), and
the strength on the label (so much in each millilitre or in each tablet).
The dose is two steps of arithmetic and one or two conversions of a unit.
People make those steps on paper beside the animals, and the usual
mistakes are a wrong unit (grams for kilograms, micrograms for
milligrams) and a lost point.

Rescord had the weight of each resident in its journal, and no page that
calculates. It also had no place for a page that helps with a piece of
work and is no record.

## Decision

- **An organisation has tools.** The site menu has the part Tools, after
  Inventory. `/o/<short name>/tools` lists the tools, each as a card with
  a line that says what it does. A tool stores nothing. Each member of the
  organisation can open a tool: no power is needed, and a tool that fills
  in a value from the records reads it as the member, so the grants of
  the member decide.
- **The dose calculator is the first tool**, at
  `/o/<short name>/tools/dose`. A member types a body weight, a dose rate
  for each kilogram, and the strength of the product when the result must
  be a volume or a number of tablets. The page gives the dose and the
  amount of the product.
- **It is an aid to arithmetic, and it knows no medication.** Rescord has
  no formulary. The page offers no dose rate, and never says that a dose
  is safe or that it is too much: a tool that warns about some wrong doses
  is trusted for all of them, and Rescord cannot know the species, the
  condition and the product. The page says so at all times, in a note
  that nothing closes, and says to check the result with a vet.
- **It shows its working.** A result has each step: a conversion, the
  multiplication, the division, each with its numbers and its units. It
  also repeats what went in, so a wrong unit is in front of the reader.
- **`Rescord.Dosage` is the arithmetic**, a module of the core with no
  resource. `read/1` reads what a person typed, `calculate/1` gives a
  result or each problem, and a result holds its steps as data. The page
  writes the steps as words (`RescordWeb.ToolWords`), so the core holds no
  words. The units, the conversions and the arithmetic of two quantities
  are `Rescord.Units` (ADR 0071): the calculator has no table of units.
- **The guards:**
  1. A number is digits with at most one point, up to 7 digits before it
     and up to 6 after it. A comma, a sign, an exponent and a point with
     no digit before it are refused, with words that say how to write the
     number: `1,095` can mean 1095 or 1.095.
  2. Each number is above zero.
  3. A unit is a choice from a list, and the core accepts only the units
     that the lists offer. `calculate/1` checks the dimensions again: a
     weight is a mass, a dose rate is a mass or a volume for each mass,
     and a strength is a mass in each volume or in each tablet.
  4. A number is a text field with the decimal keyboard of a phone, and
     not a field of the type `number`, which changes its value under the
     wheel of a mouse and takes `1e3`.
  5. The result is never stale. The page calculates when the member
     presses Calculate, and a change to a field takes the result away.
  6. A result that cannot be measured says so: less than 0.01 mL, or less
     than a quarter of a tablet. That is about the syringe and the
     tablet, and not about the medication.
  7. A microgram is written `mcg` (ADR 0071).
- **The dose rate is for each kilogram.** A rate for each pound is another
  number that is easy to mix up, so the page does not offer it. A weight
  can be in kg, g, lb or oz.
- **The body weight can come from the journal of a resident.** A member
  chooses a resident in the form, or comes from the page of a resident,
  which opens the calculator with `?resident=<id>`. The choice has the
  residents that are not gone. The page reads the journal as the member,
  and takes the newest measurement of each kind whose unit is one of the
  units of weight of the calculator. With one such measurement it fills
  in the weight. With more it asks: a measurement in grams can be the
  body weight or the food that the animal ate, and the page does not
  guess. Below the field it says the kind, the date and how many days ago
  that was. It gives no limit for an old weight: a young animal changes
  in days and an adult in months, and the member sees the date. A weight
  that the member then changes is a typed weight, and the result says
  so. The weight of one resident never stays in the form for the next.
- **A result has three figures on the page**, rounded half up, with the
  word "about" before a number that was rounded. The working has six. The
  arithmetic keeps each digit (`Decimal`, and 28 digits for a division).
  The page does not round to what a syringe or a tablet can give: it shows
  1.24 tablets, and says that a vet decides how to round.

## Consequences

- A member has the dose, with the arithmetic that a vet or a second
  person can check, on a phone beside the animals.
- The calculator cannot catch a wrong dose rate. That is by design, and
  the note says it. A later formulary would be a new decision.
- Not in the calculator: international units (a dose in IU is often
  insulin, where the syringe has a scale of its own), a percent strength,
  a dose for each square metre of body surface, and a rate of infusion.
- The calculation is not a record. A journal entry of the kind `dose`
  from a result, or a prescription that the calculator fills in, is a
  later step.
- `Rescord.Dosage` is a pure function, so the assistant (ADR 0069) can
  get it as a tool later. That is the right way for an assistant to do
  arithmetic.
- The site menu has ten parts for an organisation. The row of a wide
  screen still holds them (ADR 0061).
- The next tool is a card in `RescordWeb.ToolComponents.tools/1`, a route
  below `/tools`, and a LiveView.
