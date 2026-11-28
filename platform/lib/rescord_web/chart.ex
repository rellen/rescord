defmodule RescordWeb.Chart do
  @moduledoc """
  The geometry of a line chart of values over time (ADR 0080): the scale,
  the ticks, and the place of each point. And the weeks and the steps of
  the ramp of a heat map (ADR 0116).

  A place is a percentage of the plot, and never a pixel: `x` from the
  first instant at 0 to the last at 100, and `y` from the top tick at 0 to
  the bottom tick at 100. The chart is then as wide as its place on any
  screen, and its words keep their size (`RescordWeb.ChartComponents`).

  A value is a `Decimal` and a tick is a `Decimal`, so the label of a tick
  is exact: `0.1`, and never `0.30000000000000004`. Only a place is a
  float, and no page shows one as a number.

  This module draws nothing and knows no word. It is pure: the same points
  give the same chart.
  """

  defmodule Scale do
    @moduledoc "The ticks of the values, and the first and the last instant."
    @enforce_keys [:ticks, :from, :to]
    defstruct [:ticks, :from, :to]

    @type t :: %__MODULE__{ticks: [Decimal.t()], from: DateTime.t(), to: DateTime.t()}
  end

  defmodule Mark do
    @moduledoc """
    The place of one point. `anchor` says where the words of the point go:
    after it near the left edge, before it near the right edge.
    """
    @enforce_keys [:id, :x, :y]
    defstruct [:id, :x, :y, :band_x, :band_width, anchor: "middle"]

    @type t :: %__MODULE__{
            id: term,
            x: float,
            y: float,
            band_x: float | nil,
            band_width: float | nil,
            anchor: String.t()
          }
  end

  @typedoc "What the chart draws: an instant `at` and a `value`, and an `id` for a point that answers."
  @type point :: %{
          required(:at) => DateTime.t(),
          required(:value) => Decimal.t(),
          optional(atom) => term
        }

  # The steps of a tick, each times a power of ten, and the same again one
  # power higher.
  @steps Enum.map(~w(1 2 2.5 5 10 20 25 50), &Decimal.new/1)

  # The most gaps between ticks: six ticks.
  @gaps 5

  @doc """
  The scale of some points: three to six round ticks that hold each value,
  and the instants of the first and of the last point. `nil` for no point.

  The ticks start at zero when the least value is at most half of the
  greatest, so a weight from 310 g to 1,095 g is drawn from zero. A body
  temperature from 37.9 to 39.4 is not: its ticks are 37.5 to 39.5.

      iex> points = [
      ...>   %{at: ~U[2026-10-03 09:00:00Z], value: Decimal.new("310")},
      ...>   %{at: ~U[2026-11-28 09:00:00Z], value: Decimal.new("1095")}
      ...> ]
      iex> RescordWeb.Chart.scale(points).ticks |> Enum.map(&Decimal.to_string(&1, :normal))
      ["0", "250", "500", "750", "1000", "1250"]
  """
  @spec scale([point]) :: Scale.t() | nil
  def scale([]), do: nil

  def scale(points) do
    {least, greatest} = points |> Enum.map(& &1.value) |> Enum.min_max_by(& &1, Decimal)
    {from, to} = points |> Enum.map(& &1.at) |> Enum.min_max_by(& &1, DateTime)
    whole? = Enum.all?(points, &Decimal.integer?(&1.value))
    %Scale{ticks: ticks(least, greatest, whole?), from: from, to: to}
  end

  @doc """
  Round ticks from at or below `least` to at or above `greatest`, the
  smallest first: the smallest round step that takes six ticks or fewer.
  With `whole?`, the values are whole numbers, such as a score from 1 to
  9, and no tick is between two of them.

      iex> RescordWeb.Chart.ticks(Decimal.new("37.9"), Decimal.new("39.4"))
      ...> |> Enum.map(&Decimal.to_string(&1, :normal))
      ["37.5", "38", "38.5", "39", "39.5"]

      iex> RescordWeb.Chart.ticks(Decimal.new(4), Decimal.new(4))
      ...> |> Enum.map(&Decimal.to_string(&1, :normal))
      ["2", "3", "4", "5", "6"]

      iex> RescordWeb.Chart.ticks(Decimal.new(3), Decimal.new(5), true)
      ...> |> Enum.map(&Decimal.to_string(&1, :normal))
      ["3", "4", "5"]
  """
  @spec ticks(Decimal.t(), Decimal.t(), boolean) :: [Decimal.t()]
  def ticks(%Decimal{} = least, %Decimal{} = greatest, whole? \\ false) do
    zero = Decimal.new(0)

    least =
      if Decimal.compare(least, zero) != :lt and
           Decimal.compare(Decimal.mult(least, 2), greatest) != :gt,
         do: zero,
         else: least

    {least, greatest} = apart(least, greatest)
    raw = Decimal.div(Decimal.sub(greatest, least), @gaps)
    power = raw |> Decimal.to_float() |> :math.log10() |> Float.floor() |> trunc()

    # A step below `raw` takes more gaps than the most, so the first step
    # that fits is the smallest one.
    {first, step, gaps} =
      Enum.find_value(@steps, fn round ->
        step = Decimal.mult(round, Decimal.new(1, 1, power))
        first = least |> Decimal.div(step) |> Decimal.round(0, :floor) |> Decimal.mult(step)

        gaps =
          greatest
          |> Decimal.sub(first)
          |> Decimal.div(step)
          |> Decimal.round(0, :ceiling)
          |> Decimal.to_integer()

        if gaps <= @gaps and (not whole? or Decimal.integer?(step)), do: {first, step, gaps}
      end)

    for n <- 0..gaps, do: first |> Decimal.add(Decimal.mult(step, n)) |> Decimal.normalize()
  end

  # One value, or values that are all the same, still take a scale: a tick
  # below and a tick above.
  defp apart(least, greatest) do
    if Decimal.equal?(least, greatest) do
      by = if Decimal.equal?(least, 0), do: Decimal.new(1), else: Decimal.abs(least)
      half = Decimal.div(by, 2)
      {Decimal.sub(least, half), Decimal.add(greatest, half)}
    else
      {least, greatest}
    end
  end

  @doc """
  The place of each point on a scale, in the order of the points. Each
  mark has the band of the plot that is nearer to it than to another mark:
  a finger presses the band, and not the dot.
  """
  @spec marks([point], Scale.t()) :: [Mark.t()]
  def marks(points, %Scale{} = scale) do
    points
    |> Enum.map(&%Mark{id: Map.get(&1, :id), x: x(&1.at, scale), y: y(&1.value, scale)})
    |> bands()
  end

  defp bands(marks) do
    xs = Enum.map(marks, & &1.x)
    before = [0.0 | Enum.zip_with(xs, Enum.drop(xs, 1), &((&1 + &2) / 2))]
    after_ = Enum.drop(before, 1) ++ [100.0]

    for {mark, left, right} <- Enum.zip([marks, before, after_]) do
      %{
        mark
        | band_x: Float.round(left, 2),
          band_width: Float.round(max(right - left, 0.0), 2),
          anchor: anchor(mark.x)
      }
    end
  end

  defp anchor(x) when x < 30, do: "start"
  defp anchor(x) when x > 70, do: "end"
  defp anchor(_x), do: "middle"

  @doc """
  The line through some marks, for a plot that is 100 wide and 100 high:
  `M0 79.33L25 60`. An empty text for no mark.
  """
  @spec path([Mark.t()]) :: String.t()
  def path([]), do: ""

  def path(marks) do
    marks
    |> Enum.map_join("L", &"#{number(&1.x)} #{number(&1.y)}")
    |> then(&("M" <> &1))
  end

  @doc """
  The steps through some marks, for a count that holds its value until the
  next mark (ADR 0117): across to the next mark, then up or down to it.
  An empty text for no mark.

      iex> marks = [%RescordWeb.Chart.Mark{id: 1, x: 0.0, y: 80.0}, %RescordWeb.Chart.Mark{id: 2, x: 50.0, y: 40.0}]
      iex> RescordWeb.Chart.step_path(marks)
      "M0 80H50V40"
  """
  @spec step_path([Mark.t()]) :: String.t()
  def step_path([]), do: ""

  def step_path([first | rest]) do
    Enum.reduce(rest, "M#{number(first.x)} #{number(first.y)}", fn mark, path ->
      path <> "H#{number(mark.x)}V#{number(mark.y)}"
    end)
  end

  @doc """
  The places of bars above and below a middle line (ADR 0117), one pair for
  each `{up, down}` count: `x` and `width` of the bar from the left, and
  `up` and `down`, the height of each bar as a share of the half of the
  plot, in percent of the whole plot. The greatest count of all fills its
  half.

      iex> RescordWeb.Chart.bars([{2, 0}, {1, 4}])
      [%{x: 7.5, width: 35.0, up: 25.0, down: 0.0}, %{x: 57.5, width: 35.0, up: 12.5, down: 50.0}]
  """
  @spec bars([{non_neg_integer, non_neg_integer}]) :: [map]
  def bars([]), do: []

  def bars(pairs) do
    slot = 100 / length(pairs)
    greatest = pairs |> Enum.flat_map(fn {up, down} -> [up, down] end) |> Enum.max() |> max(1)

    for {{up, down}, index} <- Enum.with_index(pairs) do
      %{
        x: Float.round(index * slot + slot * 0.15, 2),
        width: Float.round(slot * 0.7, 2),
        up: Float.round(up / greatest * 50, 2),
        down: Float.round(down / greatest * 50, 2)
      }
    end
  end

  @doc "The place of an instant from left to right, as a percentage."
  @spec x(DateTime.t(), Scale.t()) :: float
  def x(%DateTime{} = at, %Scale{from: from, to: to}) do
    span = DateTime.diff(to, from, :second)

    # One instant has no span: the point is in the middle.
    if span == 0,
      do: 50.0,
      else: Float.round(DateTime.diff(at, from, :second) / span * 100, 2)
  end

  @doc "The place of a value from the top tick down, as a percentage."
  @spec y(Decimal.t(), Scale.t()) :: float
  def y(%Decimal{} = value, %Scale{ticks: ticks}) do
    bottom = List.first(ticks)
    top = List.last(ticks)

    top
    |> Decimal.sub(value)
    |> Decimal.div(Decimal.sub(top, bottom))
    |> Decimal.mult(100)
    |> Decimal.round(2)
    |> Decimal.to_float()
  end

  @doc """
  The Mondays of the `count` weeks that end with the week of `date`, the
  oldest first. A week starts on a Monday (ADR 0116).

      iex> RescordWeb.Chart.weeks(~D[2026-11-28], 3)
      [~D[2026-11-09], ~D[2026-11-16], ~D[2026-11-23]]
  """
  @spec weeks(Date.t(), pos_integer) :: [Date.t()]
  def weeks(%Date{} = date, count) when is_integer(count) and count > 0 do
    monday = Date.beginning_of_week(date, :monday)
    for back <- (count - 1)..0//-1, do: Date.add(monday, -7 * back)
  end

  @doc """
  The step of the ramp of a heat map for a count, against the greatest
  count of the map: `0` for none, and `1` to `4` for each quarter of the
  greatest, so the greatest is always on step 4.

      iex> Enum.map([0, 1, 5, 6, 10, 20], &RescordWeb.Chart.level(&1, 20))
      [0, 1, 1, 2, 2, 4]
  """
  @spec level(non_neg_integer, non_neg_integer) :: 0..4
  def level(0, _greatest), do: 0

  def level(count, greatest) when is_integer(count) and is_integer(greatest) and count > 0 do
    # A quarter that is begun is a step: the ceiling of four times the share.
    greatest = max(greatest, count)
    div(count * 4 + greatest - 1, greatest)
  end

  @doc """
  The step of the ramp for a share, `part` of `whole`, against the bounds
  of the steps in percent: step 1 is below the first bound, and each bound
  that the share reaches is one step more. `0` for a whole of none. The
  sum is exact: 97 of 100 reaches 97%.

      iex> RescordWeb.Chart.share_level(7, 8, [80, 90, 97])
      2

      iex> RescordWeb.Chart.share_level(97, 100, [80, 90, 97])
      4

      iex> RescordWeb.Chart.share_level(0, 0, [80, 90, 97])
      0
  """
  @spec share_level(non_neg_integer, non_neg_integer, [number]) :: 0..4
  def share_level(_part, 0, _bounds), do: 0

  def share_level(part, whole, bounds) when is_integer(part) and is_integer(whole),
    do: 1 + Enum.count(bounds, &(part * 100 >= &1 * whole))

  # A place with no zeros at its end: `25`, `79.33`.
  defp number(place) do
    place
    |> Decimal.from_float()
    |> Decimal.round(2)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
