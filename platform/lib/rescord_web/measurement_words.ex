defmodule RescordWeb.MeasurementWords do
  @moduledoc """
  The words that a page uses for the measurements of a resident over time
  (ADR 0080): a value in the unit of its series, the change from the
  measurement before, and what a chart says to a person who cannot see it.
  `measurement/1` writes one measurement in the standard unit of its kind
  (ADR 0094), for an entry of the journal and for a report.

  A number is the work of `RescordWeb.JournalWords.number/1`, a quantity of
  `RescordWeb.UnitWords.quantity/1` and a date of
  `RescordWeb.ResidentWords.date/1`, so a change of how Rescord writes one
  of them is in one place.

  A value that a member recorded in the unit of the series is written as it
  was recorded, with each digit. A value that Rescord converted, and a
  change from or to such a value, is rounded to four significant digits,
  and the table of the page shows what the member recorded beside it.
  """

  alias Rescord.Journal.Series
  alias Rescord.Journal.Series.Point
  alias Rescord.Units.Quantity
  alias RescordWeb.{JournalWords, ResidentWords, UnitWords}

  @doc """
  A value in the unit of a series: `1,095 g`, `38.5 °C`, or `4` for a
  series with no unit.

      iex> series = %Rescord.Journal.Series{kind_id: "k", label: "Score"}
      iex> RescordWeb.MeasurementWords.value(series, Decimal.new("4.0"))
      "4"
  """
  @spec value(Series.t(), Decimal.t()) :: String.t()
  def value(%Series{unit: %{} = unit}, %Decimal{} = value),
    do: UnitWords.quantity(%Quantity{value: value, unit: unit})

  def value(%Series{unit_label: label}, %Decimal{} = value) when is_binary(label),
    do: "#{JournalWords.number(value)} #{label}"

  def value(%Series{}, %Decimal{} = value), do: JournalWords.number(value)

  @doc """
  One measurement in the standard unit of its kind (ADR 0094): `610 g`,
  and `610 g (recorded as 0.61 kg)` when Rescord converted it. A
  measurement of a kind with no standard unit, and one that does not
  convert, is written as it was recorded. The measurement has its unit
  and its kind with the standard unit, as `Rescord.Journal.entries/2`
  gives it.
  """
  @spec measurement(map) :: String.t()
  def measurement(measurement) do
    standard = Rescord.Journal.standard(measurement)

    if standard.converted? do
      recorded = %Point{
        entry_id: nil,
        at: nil,
        value: standard.recorded,
        recorded: standard.recorded,
        recorded_unit: standard.recorded_unit
      }

      "#{amount(four_digits(standard.value), standard)} (recorded as #{recorded(recorded)})"
    else
      amount(standard.value, standard)
    end
  end

  defp amount(value, %{unit: %{} = unit}),
    do: UnitWords.quantity(%Quantity{value: value, unit: unit})

  defp amount(value, %{unit_label: label}) when is_binary(label),
    do: "#{JournalWords.number(value)} #{label}"

  defp amount(value, _no_unit), do: JournalWords.number(value)

  @doc "The value of a point for a person, rounded when Rescord converted it."
  @spec shown(Series.t(), Point.t()) :: String.t()
  def shown(%Series{} = series, %Point{converted?: true} = point),
    do: value(series, four_digits(point.value))

  def shown(%Series{} = series, %Point{} = point), do: value(series, point.value)

  @doc "What the member recorded: `870 g`, in the unit of that measurement."
  @spec recorded(Point.t()) :: String.t()
  def recorded(%Point{recorded: value, recorded_unit: nil}), do: JournalWords.number(value)

  def recorded(%Point{recorded: value, recorded_unit: unit}),
    do: "#{JournalWords.number(value)} #{unit}"

  @doc """
  The change of a point from the point before it, as its direction and the
  amount with no sign: `{:up, "45 g"}`. `nil` for the first point.
  """
  @spec change(Series.t(), Point.t()) :: {:up | :down | :same, String.t()} | nil
  def change(%Series{}, %Point{change: nil}), do: nil

  def change(%Series{} = series, %Point{change: change}) do
    amount = value(series, change |> Decimal.abs() |> four_digits())

    case Decimal.compare(change, 0) do
      :gt -> {:up, amount}
      :lt -> {:down, amount}
      :eq -> {:same, amount}
    end
  end

  @doc """
  The change of a point in words: `45 g more than on 21 November 2026`.
  `date` writes the instant of the point before.
  """
  @spec change_words(Series.t(), Point.t(), (DateTime.t() -> String.t())) :: String.t() | nil
  def change_words(%Series{} = series, %Point{} = point, date) do
    case change(series, point) do
      nil -> nil
      {:up, amount} -> "#{amount} more than on #{date.(point.before)}"
      {:down, amount} -> "#{amount} less than on #{date.(point.before)}"
      {:same, _amount} -> "The same as on #{date.(point.before)}"
    end
  end

  @doc """
  What a chart of a series shows, for a person who does not see it: how
  many measurements, from when to when, the lowest, the highest and the
  newest. `date` writes an instant.
  """
  @spec summary(Series.t(), (DateTime.t() -> String.t())) :: String.t()
  def summary(%Series{points: []}, _date), do: "No measurement."

  def summary(%Series{points: [point]} = series, date),
    do: "One measurement: #{shown(series, point)} on #{date.(point.at)}."

  def summary(%Series{points: points} = series, date) do
    {lowest, highest} = Series.extent(series)
    first = List.first(points)
    newest = List.last(points)

    "#{length(points)} measurements from #{date.(first.at)} to #{date.(newest.at)}. " <>
      "The lowest is #{shown(series, lowest)}, on #{date.(lowest.at)}. " <>
      "The highest is #{shown(series, highest)}, on #{date.(highest.at)}. " <>
      "The newest is #{shown(series, newest)}."
  end

  @doc """
  A function that writes an instant of a series for an organisation: the
  date, and the time of the day too when two points of the series are on
  one day.
  """
  @spec date_of(Series.t(), term) :: (DateTime.t() -> String.t())
  def date_of(%Series{points: points}, organisation) do
    days = Enum.map(points, &Rescord.Accounts.local_date(organisation, &1.at))

    if days == Enum.uniq(days) do
      &ResidentWords.date(Rescord.Accounts.local_date(organisation, &1))
    else
      &JournalWords.time(Rescord.Accounts.local_time(organisation, &1))
    end
  end

  @doc """
  A number with four significant digits, and each digit before the point.

      iex> RescordWeb.MeasurementWords.four_digits(Decimal.new("0.90718474")) |> Decimal.to_string()
      "0.9072"

      iex> RescordWeb.MeasurementWords.four_digits(Decimal.new("12345.67")) |> Decimal.to_string()
      "12346"
  """
  @spec four_digits(Decimal.t()) :: Decimal.t()
  def four_digits(%Decimal{} = value) do
    if Decimal.equal?(value, 0) do
      Decimal.new(0)
    else
      # The place of the first digit that is not zero: 0 for 1 to 9, -1 for 0.1 to 0.9.
      %Decimal{coef: coef, exp: exp} = Decimal.normalize(value)
      first = length(Integer.digits(coef)) - 1 + exp
      value |> Decimal.round(max(3 - first, 0)) |> Decimal.normalize()
    end
  end
end
