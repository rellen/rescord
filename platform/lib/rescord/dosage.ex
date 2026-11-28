defmodule Rescord.Dosage do
  @moduledoc """
  The arithmetic of a dose: a body weight times a dose rate, and then the
  volume or the number of tablets that holds that dose (ADR 0072). The dose
  calculator of the tools is its page.

  It is an aid to arithmetic, and three rules hold.

    * **It knows no medication.** There is no formulary. Nothing here offers
      a dose rate, or says that a dose is safe or too much. The dose rate
      and the strength come from a vet or from a label.
    * **It stores nothing.** The module has no resource and reads no
      database.
    * **It shows its working.** A result holds each step as data, with the
      numbers and the units that went in and came out. A page writes the
      steps as words, so this module holds no words.

  The units, the conversions and the arithmetic of two quantities are
  `Rescord.Units` (ADR 0071). This module adds what is about a dose and not
  about a unit: which units a weight, a dose rate and a strength can have,
  how a person writes a number, the steps, how a result is rounded for a
  page, and when a result is too small to measure.

      iex> {:ok, given} =
      ...>   Rescord.Dosage.read(%{
      ...>     weight: "1095",
      ...>     weight_unit: "g",
      ...>     rate: "0.2",
      ...>     rate_unit: "mg",
      ...>     strength: "1.5",
      ...>     strength_unit: "mg",
      ...>     strength_per: "mL"
      ...>   })
      iex> {:ok, result} = Rescord.Dosage.calculate(given)
      iex> {to_string(result.dose), to_string(result.amount)}
      {"0.219 mg", "0.146 mL"}
  """

  alias Rescord.Units
  alias Rescord.Units.Quantity

  defmodule Result do
    @moduledoc """
    What a calculation gave: the three quantities that went in, the dose, the
    amount of the product that holds the dose (with a strength), the steps
    of the working in their order, and the notes about a result that is too
    small to measure.

    A step is one of:

      * `{:convert, from, to}` - the same quantity in another unit;
      * `{:multiply, weight, rate, dose}` - the weight times the dose rate;
      * `{:divide, dose, strength, amount}` - the dose by the strength.

    The numbers are exact. `Rescord.Dosage.round_figures/2` rounds one for a
    page.
    """

    @enforce_keys [:weight, :rate, :dose]
    defstruct [:weight, :rate, :strength, :dose, :amount, steps: [], notes: []]

    @type step ::
            {:convert, Quantity.t(), Quantity.t()}
            | {:multiply, Quantity.t(), Quantity.t(), Quantity.t()}
            | {:divide, Quantity.t(), Quantity.t(), Quantity.t()}

    @type t :: %__MODULE__{
            weight: Quantity.t(),
            rate: Quantity.t(),
            strength: Quantity.t() | nil,
            dose: Quantity.t(),
            amount: Quantity.t() | nil,
            steps: [step],
            notes: [Rescord.Dosage.note()]
          }
  end

  @typedoc "The part of a calculation that a problem is about."
  @type field :: :weight | :rate | :strength | :calculation

  @typedoc """
  Why a value was refused. A page has words for each
  (`RescordWeb.ToolWords`).
  """
  @type reason ::
          :blank
          | :not_a_number
          | :not_positive
          | :unknown_unit
          | :not_a_weight
          | :not_a_dose_rate
          | :not_a_strength
          | :not_for_a_volume
          | :units_do_not_fit

  @type problem :: {field, reason}

  @typedoc "What a result says about itself: it is too small to measure."
  @type note :: :too_small_to_measure | :less_than_a_quarter

  @typedoc "The three quantities of a calculation. The strength can be absent."
  @type given :: %{
          required(:weight) => Quantity.t(),
          required(:rate) => Quantity.t(),
          optional(:strength) => Quantity.t() | nil
        }

  # The units that the calculator offers, each list in the order of its
  # select. The first of a list is the unit that a new form shows.
  @weight_units ~w(kg g lb oz)
  @dose_units ~w(mg mcg g mL)
  @strength_units ~w(mg mcg g)
  @strength_per ~w(mL tablet)

  # A dose rate is always for each kilogram of body weight. A rate for each
  # pound is another number, which is easy to mix up.
  @per "kg"

  # A number as a person writes it: digits, and at most one point with
  # digits on both sides. No comma, no sign, no exponent.
  @number ~r/\A\d{1,7}(\.\d{1,6})?\z/

  # The least volume that a 1 mL syringe measures, and the least part of a
  # tablet that a person can cut.
  @least_volume {Decimal.new("0.01"), "mL"}
  @least_tablet Decimal.new("0.25")

  # The figures of a result on a page.
  @figures 3

  # Each problem that `read/1` or `calculate/1` can give, by its field.
  @problems [
    weight: [:blank, :not_a_number, :not_positive, :unknown_unit, :not_a_weight],
    rate: [:blank, :not_a_number, :not_positive, :unknown_unit, :not_a_dose_rate],
    strength: [:not_a_number, :not_positive, :unknown_unit, :not_a_strength, :not_for_a_volume],
    calculation: [:units_do_not_fit]
  ]

  @notes [:too_small_to_measure, :less_than_a_quarter]

  @doc "Each problem that a calculation can give, for the page that has words for it."
  @spec problems() :: [problem]
  def problems, do: for({field, reasons} <- @problems, reason <- reasons, do: {field, reason})

  @doc "Each note that a result can have, for the page that has words for it."
  @spec notes() :: [note]
  def notes, do: @notes

  @doc "The units of a body weight, in the order of the select."
  @spec weight_units() :: [Units.Unit.t()]
  def weight_units, do: units(@weight_units)

  @doc """
  The units of the amount of a dose rate, in the order of the select. The
  rate is that amount for each kilogram of body weight.
  """
  @spec dose_units() :: [Units.Unit.t()]
  def dose_units, do: units(@dose_units)

  @doc "The units of the amount of a strength, in the order of the select."
  @spec strength_units() :: [Units.Unit.t()]
  def strength_units, do: units(@strength_units)

  @doc "What a strength is in each of: a millilitre or a tablet."
  @spec strength_per() :: [Units.Unit.t()]
  def strength_per, do: units(@strength_per)

  defp units(codes) do
    Enum.map(codes, fn code ->
      {:ok, unit} = Units.parse(code)
      unit
    end)
  end

  @doc """
  Whether a dose rate with this unit of amount gives a volume, so that a
  strength has no part in the calculation: `"mL"`.
  """
  @spec volume?(term) :: boolean
  def volume?(code) when code in @dose_units, do: Units.dimension(code) == :volume
  def volume?(_code), do: false

  @doc """
  Reads a number that a person typed. A number is digits with at most one
  point: up to 7 digits before it and up to 6 after it, and above zero.

  A comma is refused, because `1,095` can mean 1095 or 1.095. So are a
  sign, an exponent, and a point with no digit before it: a person writes
  `0.5`, never `.5`.

      iex> Rescord.Dosage.parse_number(" 0.25 ")
      {:ok, Decimal.new("0.25")}

      iex> Rescord.Dosage.parse_number("1,095")
      {:error, :not_a_number}

      iex> Rescord.Dosage.parse_number(".5")
      {:error, :not_a_number}

      iex> Rescord.Dosage.parse_number("1e3")
      {:error, :not_a_number}

      iex> Rescord.Dosage.parse_number("0.0")
      {:error, :not_positive}

      iex> Rescord.Dosage.parse_number("")
      {:error, :blank}
  """
  @spec parse_number(term) ::
          {:ok, Decimal.t()} | {:error, :blank | :not_a_number | :not_positive}
  def parse_number(nil), do: {:error, :blank}

  def parse_number(text) when is_binary(text) do
    text = String.trim(text)

    cond do
      text == "" ->
        {:error, :blank}

      not Regex.match?(@number, text) ->
        {:error, :not_a_number}

      true ->
        number = Decimal.new(text)
        if Decimal.positive?(number), do: {:ok, number}, else: {:error, :not_positive}
    end
  end

  def parse_number(_other), do: {:error, :not_a_number}

  @doc """
  Reads what a person typed and chose into the quantities of a
  calculation, or says each value that it refuses.

  `typed` has the text of each number and the code of each unit, under
  `:weight`, `:weight_unit`, `:rate`, `:rate_unit`, `:strength`,
  `:strength_unit` and `:strength_per`. A unit that the calculator does
  not offer is refused, so a request that a person forged gets no result.

  The strength is absent when its number is blank. It is also absent when
  the dose rate gives a volume, because the page then shows no strength.
  """
  @spec read(map) :: {:ok, given} | {:error, [problem]}
  def read(typed) when is_map(typed) do
    weight = quantity(typed[:weight], weight_unit(typed[:weight_unit]))
    rate = quantity(typed[:rate], rate_unit(typed[:rate_unit]))
    strength = read_strength(typed)

    case for {field, {:error, reason}} <- [weight: weight, rate: rate, strength: strength],
             do: {field, reason} do
      [] ->
        {:ok, %{weight: value(weight), rate: value(rate), strength: value(strength)}}

      problems ->
        {:error, problems}
    end
  end

  defp read_strength(typed) do
    cond do
      volume?(typed[:rate_unit]) ->
        {:ok, nil}

      parse_number(typed[:strength]) == {:error, :blank} ->
        {:ok, nil}

      true ->
        quantity(typed[:strength], strength_unit(typed[:strength_unit], typed[:strength_per]))
    end
  end

  defp value({:ok, value}), do: value

  defp quantity(number, unit) do
    with {:ok, number} <- parse_number(number),
         {:ok, unit} <- unit do
      Quantity.new(number, unit)
    end
  end

  defp weight_unit(code) when code in @weight_units, do: unit(code)
  defp weight_unit(_code), do: {:error, :unknown_unit}

  defp rate_unit(code) when code in @dose_units, do: unit("#{code}/#{@per}")
  defp rate_unit(_code), do: {:error, :unknown_unit}

  defp strength_unit(code, per) when code in @strength_units and per in @strength_per,
    do: unit("#{code}/#{per}")

  defp strength_unit(_code, _per), do: {:error, :unknown_unit}

  defp unit(code) do
    case Units.parse(code) do
      {:ok, unit} -> {:ok, unit}
      :error -> {:error, :unknown_unit}
    end
  end

  @doc """
  Calculates the dose, and with a strength the amount of the product that
  holds it.

    1. The weight in the unit of the dose rate (a weight in g, a rate for
       each kg).
    2. The dose: the weight times the dose rate.
    3. With a strength: the dose in the unit of the strength, and then the
       amount, which is the dose by the strength.

  It checks the quantities again, whoever made them: the weight is a mass,
  the dose rate is a mass or a volume for each mass, the strength is a mass
  in each volume or in each tablet, and each number is above zero. A
  strength has no meaning for a dose rate that gives a volume, so that is
  refused, and not ignored.

      iex> {:ok, weight} = Rescord.Units.Quantity.parse("12.4 kg")
      iex> {:ok, rate} = Rescord.Units.Quantity.parse("5 mg/kg")
      iex> {:ok, strength} = Rescord.Units.Quantity.parse("50 mg/tablet")
      iex> {:ok, result} =
      ...>   Rescord.Dosage.calculate(%{weight: weight, rate: rate, strength: strength})
      iex> to_string(result.amount)
      "1.24 tablet"

      iex> {:ok, weight} = Rescord.Units.Quantity.parse("5 mL")
      iex> {:ok, rate} = Rescord.Units.Quantity.parse("5 mg/kg")
      iex> Rescord.Dosage.calculate(%{weight: weight, rate: rate})
      {:error, [weight: :not_a_weight]}
  """
  @spec calculate(given) :: {:ok, Result.t()} | {:error, [problem]}
  def calculate(%{weight: %Quantity{} = weight, rate: %Quantity{} = rate} = given) do
    strength = Map.get(given, :strength)

    with [] <- problems(weight, rate, strength),
         {:ok, weight_for, steps} <- in_unit(weight, rate.unit.denominator, []),
         {:ok, dose} <- Units.multiply(rate, weight_for),
         dose = tidy(dose),
         steps = [{:multiply, weight_for, rate, dose} | steps],
         {:ok, amount, steps} <- amount(dose, strength, steps) do
      {:ok,
       %Result{
         weight: weight,
         rate: rate,
         strength: strength,
         dose: dose,
         amount: amount,
         steps: Enum.reverse(steps),
         notes: notes(amount || dose)
       }}
    else
      [_ | _] = problems -> {:error, problems}
      {:error, _reason} -> {:error, [calculation: :units_do_not_fit]}
    end
  end

  def calculate(_other), do: {:error, [calculation: :units_do_not_fit]}

  defp problems(weight, rate, strength) do
    rate_dimension = Units.dimension(rate.unit)

    List.flatten([
      check(:weight, weight, Units.dimension(weight.unit) == :mass, :not_a_weight),
      check(:rate, rate, rate_dimension in [{:mass, :mass}, {:volume, :mass}], :not_a_dose_rate),
      strength_problems(strength, rate_dimension)
    ])
  end

  defp strength_problems(nil, _rate_dimension), do: []

  defp strength_problems(%Quantity{} = strength, rate_dimension) do
    fits? = Units.dimension(strength.unit) in [{:mass, :volume}, {:mass, :tablet}]

    cond do
      not fits? -> [strength: :not_a_strength]
      rate_dimension == {:volume, :mass} -> [strength: :not_for_a_volume]
      true -> check(:strength, strength, true, :not_a_strength)
    end
  end

  defp strength_problems(_other, _rate_dimension), do: [strength: :not_a_strength]

  # The dimension first, and then the number: a quantity of the wrong kind
  # has no number worth a word.
  defp check(field, _quantity, false, reason), do: [{field, reason}]

  defp check(field, %Quantity{value: value}, true, _reason) do
    if Decimal.positive?(value), do: [], else: [{field, :not_positive}]
  end

  defp amount(_dose, nil, steps), do: {:ok, nil, steps}

  defp amount(dose, strength, steps) do
    with {:ok, dose_for, steps} <- in_unit(dose, strength.unit.numerator, steps),
         {:ok, amount} <- Units.divide(dose_for, strength) do
      amount = tidy(amount)
      {:ok, amount, [{:divide, dose_for, strength, amount} | steps]}
    end
  end

  # The quantity in another unit, with the step that says so when the unit
  # changes. The arithmetic after it then converts nothing out of sight.
  defp in_unit(%Quantity{unit: unit} = quantity, unit, steps), do: {:ok, quantity, steps}

  defp in_unit(quantity, unit, steps) do
    with {:ok, converted} <- Quantity.convert(quantity, unit) do
      converted = tidy(converted)
      {:ok, converted, [{:convert, quantity, converted} | steps]}
    end
  end

  # No zeros after the last digit: 62 and never 62.0, which a person can
  # read as 620.
  defp tidy(%Quantity{value: value} = quantity),
    do: %{quantity | value: Decimal.normalize(value)}

  defp notes(%Quantity{} = result) do
    {least, unit} = @least_volume

    case Units.dimension(result.unit) do
      :volume ->
        case Units.convert(result.value, result.unit, unit) do
          {:ok, volume} -> if Decimal.lt?(volume, least), do: [:too_small_to_measure], else: []
          {:error, _reason} -> []
        end

      :tablet ->
        if Decimal.lt?(result.value, @least_tablet), do: [:less_than_a_quarter], else: []

      _other ->
        []
    end
  end

  @doc """
  A number with the figures that a page shows, three of them, rounded half
  up, and whether that is the exact number. A page writes "about" before a
  number that is not exact.

      iex> Rescord.Dosage.round_figures(Decimal.new("0.146"))
      {Decimal.new("0.146"), true}

      iex> Rescord.Dosage.round_figures(Decimal.new("0.41666"))
      {Decimal.new("0.417"), false}

      iex> Rescord.Dosage.round_figures(Decimal.new("1234.5"))
      {Decimal.new("1.23E+3"), false}

      iex> Rescord.Dosage.round_figures(Decimal.new("0.9996"))
      {Decimal.new("1"), false}

      iex> Rescord.Dosage.round_figures(Decimal.new("0.123456"), 6)
      {Decimal.new("0.123456"), true}
  """
  @spec round_figures(Decimal.t(), pos_integer) :: {Decimal.t(), boolean}
  def round_figures(%Decimal{} = number, figures \\ @figures)
      when is_integer(figures) and figures > 0 do
    if Decimal.equal?(number, 0) do
      {Decimal.new(0), true}
    else
      # The place of the first figure: 0 for 1 to 9, -1 for 0.1 to 0.9.
      first = length(Integer.digits(number.coef)) + number.exp - 1
      rounded = number |> Decimal.round(figures - 1 - first, :half_up) |> Decimal.normalize()

      {rounded, Decimal.equal?(rounded, number)}
    end
  end
end
