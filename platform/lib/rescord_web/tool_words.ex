defmodule RescordWeb.ToolWords do
  @moduledoc """
  The words that a page uses for the tools: a quantity of the dose
  calculator, a step of its working, why it refused a value, and what it
  says about a result. A page never shows the atom of a value.
  `RescordWeb.ToolWordsTest` holds the lists to the types of
  `Rescord.Dosage`.
  """

  alias Rescord.Dosage
  alias Rescord.Units.Quantity
  alias RescordWeb.{ResidentWords, UnitWords}

  # The figures of a number in the working. A result has three
  # (`Rescord.Dosage.round_figures/2`), and the working has more, so a
  # person can check it.
  @working_figures 6

  # How to write a number, for each refusal of one.
  @write "Write the number with digits and a point, and no comma: 1095 or 0.5."

  @problems [
    weight: [
      blank: "Type the body weight.",
      not_a_number: @write,
      not_positive: "The body weight must be above zero.",
      unknown_unit: "Choose the unit of the body weight from the list.",
      not_a_weight: "The body weight must be a mass, such as kg or g."
    ],
    rate: [
      blank: "Type the dose rate.",
      not_a_number: @write,
      not_positive: "The dose rate must be above zero.",
      unknown_unit: "Choose the unit of the dose rate from the list.",
      not_a_dose_rate: "The dose rate must be a mass or a volume for each kg of body weight."
    ],
    strength: [
      not_a_number: @write,
      not_positive: "The strength must be above zero.",
      unknown_unit: "Choose the units of the strength from the lists.",
      not_a_strength: "The strength must be a mass in each mL or in each tablet.",
      not_for_a_volume: "A dose rate in mL already gives a volume. It takes no strength."
    ],
    calculation: [
      units_do_not_fit: "These units do not fit each other, so there is no result."
    ]
  ]

  @notes [
    too_small_to_measure:
      "This is less than 0.01 mL, which a 1 mL syringe cannot measure. Ask your vet how to give it.",
    less_than_a_quarter:
      "This is less than a quarter of a tablet, which nobody can cut well. Ask your vet how to give it."
  ]

  @doc "Why the calculator refused a value, in words for a person."
  @spec problem(Dosage.problem()) :: String.t()
  def problem({field, reason}), do: @problems |> Keyword.fetch!(field) |> Keyword.fetch!(reason)

  @doc "Each problem that has words, for the test that holds them."
  @spec problems() :: [Dosage.problem()]
  def problems do
    for {field, reasons} <- @problems, {reason, _words} <- reasons, do: {field, reason}
  end

  @doc "What the calculator says about a result that is too small to measure."
  @spec note(Dosage.note()) :: String.t()
  def note(note), do: Keyword.fetch!(@notes, note)

  @doc "Each note that has words, for the test that holds them."
  @spec notes() :: [Dosage.note()]
  def notes, do: Keyword.keys(@notes)

  @doc """
  A quantity as a person typed it or as a record holds it, with each
  digit: `1,095 g`, `1.24 tablets`.
  """
  @spec quantity(Quantity.t()) :: String.t()
  def quantity(%Quantity{} = quantity), do: UnitWords.quantity(quantity)

  @doc """
  A quantity that the calculator worked out, with at most `figures`
  figures. The word "about" is before a number that was rounded:
  `about 0.417 mL`.
  """
  @spec worked(Quantity.t(), pos_integer) :: String.t()
  def worked(%Quantity{value: value} = quantity, figures \\ 3) do
    case Dosage.round_figures(value, figures) do
      {_same, true} -> quantity(quantity)
      {rounded, false} -> "about " <> quantity(%{quantity | value: rounded})
    end
  end

  @doc "A dose rate in a sentence: `0.2 mg for each kg of body weight`."
  @spec rate(Quantity.t()) :: String.t()
  def rate(%Quantity{unit: unit} = rate) do
    "#{UnitWords.quantity(%{rate | unit: unit.numerator})} for each " <>
      "#{unit.denominator.symbol} of body weight"
  end

  @doc "A strength in a sentence: `1.5 mg in each mL`, `50 mg in each tablet`."
  @spec strength(Quantity.t()) :: String.t()
  def strength(%Quantity{unit: unit} = strength) do
    "#{UnitWords.quantity(%{strength | unit: unit.numerator})} in each #{unit.denominator.symbol}"
  end

  @doc """
  A measurement of the journal that can be the body weight, in one line:
  `Weight: 1,095 g, 16 November 2026, 12 days ago`.
  """
  @spec measurement(map) :: String.t()
  def measurement(%{kind: kind, quantity: quantity, on: on, days: days}) do
    "#{kind}: #{quantity(quantity)}, #{when_measured(on, days)}"
  end

  @doc """
  Where the body weight of the form came from:
  `From the journal of Biscuit: Weight, 16 November 2026, 12 days ago.`
  """
  @spec source(map) :: String.t()
  def source(%{resident: resident, kind: kind, on: on, days: days}) do
    "From the journal of #{resident}: #{kind}, #{when_measured(on, days)}."
  end

  # The date of a measurement and how old it is. The calculator gives no
  # limit for an old weight: a young animal changes in days.
  defp when_measured(%Date{} = on, days),
    do: Enum.join([ResidentWords.date(on) | ago(days)], ", ")

  @doc "How long ago a day was, in words: `today`, `yesterday`, `12 days ago`."
  @spec ago(integer) :: [String.t()]
  def ago(0), do: ["today"]
  def ago(1), do: ["yesterday"]
  def ago(days) when is_integer(days) and days > 1, do: ["#{days} days ago"]
  def ago(_days), do: []

  @doc """
  A step of the working in one line, as a person writes arithmetic:
  `1,095 g = 1.095 kg`, `1.095 kg × 0.2 mg/kg = 0.219 mg`,
  `0.219 mg ÷ 1.5 mg/mL = 0.146 mL`.
  """
  @spec step(Dosage.Result.step()) :: String.t()
  def step({:convert, from, to}), do: "#{number(from)} = #{number(to)}"

  def step({:multiply, weight, rate, dose}),
    do: "#{number(weight)} × #{number(rate)} = #{number(dose)}"

  def step({:divide, dose, strength, amount}),
    do: "#{number(dose)} ÷ #{number(strength)} = #{number(amount)}"

  defp number(quantity), do: worked(quantity, @working_figures)
end
