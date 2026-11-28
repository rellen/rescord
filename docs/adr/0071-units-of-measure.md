# ADR 0071: Units of measure

Status: accepted (the maintainer asked on 28 November 2026 whether Rescord
models units of measure; the decisions below are of this ADR, and the
maintainer can change them). The design is in issue 5 of the repository.

## Context

Rescord had units only as names.

- `Rescord.Lists.Unit` is a list that an organisation can extend: `g`,
  `kg`, `bag`. A value had no dimension and no factor.
- A measurement is a decimal and a value of that list (ADR 0039). The
  quantities of the inventory are decimals in the unit of the item
  (ADR 0034).
- The dose of a prescription and the amount of a dose are text.

No code converted a quantity, and nothing knew a unit such as mg/kg or
mg/mL. A dosage calculator needs both, and a wrong conversion there is a
wrong dose.

## Decision

- **`Rescord.Units` holds a catalogue of units in the code.** It is a
  plain module of the core with no database. The catalogue has what a
  refuge measures and doses with: a mass (mcg, mg, g, kg, oz, lb), a volume
  (mL, L), a length (mm, cm, m, in), a temperature (°C, °F), a time (s,
  min, h, d), an energy (kJ, kcal), three counts (tablet, capsule, drop)
  and the international unit (IU). Each unit has an exact factor to the
  base unit of its dimension.
- **Each number is a `Decimal`.** No function takes or returns a float. A
  conversion is one division after each multiplication, with 28
  significant digits, so a result that can be exact is exact. A caller
  rounds for a page, with `Rescord.Units.Quantity.round/2`. The module
  rounds nothing: how a dose rounds is a decision of the page that shows
  it.
- **A quantity carries its unit**: `%Rescord.Units.Quantity{value, unit}`.
  `multiply/2`, `divide/2`, `add/2` and `subtract/2` of `Rescord.Units`
  check the units, and return an error for units that do not fit. No
  function raises for a text that a person typed.
- **A ratio is one unit of the catalogue for each of another**: `mg/kg`,
  `mg/mL`, `mg/tablet`, `IU/mL`, `mL/h`. A ratio never cancels: `mg/kg`
  is a mass of a medication for each mass of a body, with the dimension
  `{:mass, :mass}`, and it is not a plain number. A temperature is no part
  of a ratio.
- **A count and an international unit convert to nothing.** Each count is
  a dimension of its own. The size of an IU depends on the substance.
- **The symbol of a microgram is `mcg`.** `parse/1` reads `µg` and `ug`.
  Rescord never writes a `µ`: a person can read it as an `m`, which is a
  dose 1,000 times too large.
- **`parse/1` reads the symbol as it is, and then with no regard to the
  case**, with other spellings: `ml`, `Kilograms`, `lbs`, `millilitre`,
  `milliliter`. No two units share a spelling, and the compiler stops for
  a catalogue that breaks this. The catalogue has no megagram, so `MG` is
  a milligram.
- **A number in a text has a point and no comma**: `12.5 kg`. A comma is
  the mark of a thousand in one country and of a decimal in another, so
  `Quantity.parse/1` refuses it.
- **The list of units of an organisation stays, and the name of a value is
  its meaning.** The list says which units the forms of an organisation
  offer. `Rescord.Lists.known_unit/1` asks the catalogue about the name of
  a value: it knows `kg`, and it does not know `bag`. A unit that the
  catalogue does not know works as before, and Rescord does not convert
  it. `Rescord.Journal.quantity/1` gives a measurement as a quantity.
- **No column says what a value of the list means.** The name says it
  already, so a column could only disagree with it. No temporal table
  changes, each record of today is understood at once, and a transfer and
  an export, which carry the name, lose nothing.
- **Two Ash types.** `Rescord.Units.Types.Unit` stores the code of a unit
  as text. `Rescord.Units.Types.Quantity` stores a map,
  `{"value": "0.2", "unit": "mL"}`: the number is text, so no digit is
  lost. It reads the text `0.2 mL` of a form. Each has the constraint
  `dimension`, one dimension or a list, and a quantity has `positive?`.
  Nothing stores a number in a base unit: a record keeps the unit that the
  person wrote.
- **No library.** The package `localize`, the successor of `ex_cldr`, has
  a unit engine from CLDR. A test on 28 November 2026 (localize 1.11.0)
  showed that it takes a `Decimal`, that it keeps `milligram-per-kilogram`
  as a mass for each mass, and that it converts with the prefixes of SI
  exactly. It also showed that a factor that does not end passes through a
  float (1 inch in feet was right to 16 digits), that a float in gives a
  float out, and that it knows no tablet and no international unit. Rescord
  needs about 25 units and exact arithmetic for a dose, which is one
  module with each factor in a test. The key of a unit follows the name of
  CLDR where CLDR has the unit (`:kilogram`, `:milliliter`), so a later
  step can take the name of a unit in a language from `localize`.
- **Not in the catalogue, on purpose:** a teaspoon, a cup and a fluid
  ounce, which differ between countries, and a percent, which can be a
  weight in a volume, a weight in a weight, or a change.

## Consequences

- The dosage calculator has `convert/3`, the ratios and the arithmetic,
  and writes none of its own.
- A page writes a quantity with one function of the web layer,
  `RescordWeb.UnitWords.quantity/1`: the number, and then the symbol. The
  symbol is the same in each language. The number goes through
  `RescordWeb.JournalWords.number/1`, so a change of how a page writes a
  number is in one place.
- An organisation that names a unit in its own words, such as `scoop` or
  `kilo bag`, gets no conversion for it. The lists page says for each unit
  what Rescord knows, so an administrator sees how to name one. If a local
  name needs a meaning, a later ADR can add a column.
- `mg/kg` times a mass gives a mass. The model cannot tell the mass of a
  body from the mass of a medication: `5 mg/kg` times `2 mg` has an
  answer. The page that calculates asks for a weight, and holds that.
- A ratio has two units. A rate for each kilogram for each day
  (`mg/kg/d`) is not a unit here.
- A percent solution, a strength of an item and a dose rate of a
  prescription as quantities, the change of a weight between two
  measurements, and the pack size of an item ("a bag of 20 kg") are later
  steps.
- No table and no record changed.
