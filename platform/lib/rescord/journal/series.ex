defmodule Rescord.Journal.Series do
  @moduledoc """
  The measurements of one kind for one resident, in the order of time: what
  a chart of the weight draws.

  A series has one unit: the standard unit of its kind (ADR 0094). A kind
  with no standard unit has the unit of its newest measurement. A
  measurement in another unit is a point of the series when Rescord can
  convert it (ADR 0071): 870 g is 0.87 kg. A measurement that does not
  convert, such as one with no unit in a series of grams, is in `others`,
  and a page says that it is not in the chart.

  Each number is a `Decimal`. A point keeps what the member recorded, in
  `recorded` and `recorded_unit`, beside its value in the unit of the
  series. `change` is the value less the value of the point before it.

  This module reads no database. `Rescord.Journal.series/2` gives it the
  entries.
  """

  alias Rescord.Journal.Standard
  alias Rescord.Units

  defmodule Point do
    @moduledoc "One measurement of a series."

    @enforce_keys [:entry_id, :at, :value, :recorded]
    defstruct [
      :entry_id,
      :at,
      :value,
      :recorded,
      :recorded_unit,
      :change,
      :before,
      :note,
      converted?: false
    ]

    @type t :: %__MODULE__{
            entry_id: String.t(),
            at: DateTime.t(),
            value: Decimal.t(),
            recorded: Decimal.t(),
            recorded_unit: String.t() | nil,
            change: Decimal.t() | nil,
            before: DateTime.t() | nil,
            note: String.t() | nil,
            converted?: boolean
          }
  end

  @enforce_keys [:kind_id, :label]
  defstruct [
    :kind_id,
    :label,
    :unit_id,
    :unit_label,
    :unit,
    standard?: false,
    points: [],
    others: []
  ]

  @type t :: %__MODULE__{
          kind_id: String.t(),
          label: String.t(),
          unit_id: String.t() | nil,
          unit_label: String.t() | nil,
          unit: Units.Unit.t() | nil,
          standard?: boolean,
          points: [Point.t()],
          others: [Point.t()]
        }

  @doc """
  The series of the journal entries of one resident, one for each measure
  kind, in the order of the names of the kinds. Each entry has its
  measurement with the kind and the unit, as `Rescord.Journal` loads them.
  An entry with no measurement is ignored.
  """
  @spec from_entries([map]) :: [t]
  def from_entries(entries) do
    entries
    |> Enum.filter(&match?(%{measurement: %{value: %Decimal{}}}, &1))
    |> Enum.group_by(& &1.measurement.measure_kind_id)
    |> Enum.map(fn {_kind_id, of_kind} -> build(of_kind) end)
    |> Enum.sort_by(&String.downcase(&1.label))
  end

  defp build(entries) do
    entries = Enum.sort_by(entries, &{DateTime.to_unix(&1.happened_at, :microsecond), &1.id})
    newest = List.last(entries).measurement
    standard = Standard.standard_unit(newest)

    # The unit of the series: a value of the list of units, or `nil` for
    # a series with no unit.
    of_series = standard || loaded(newest.unit)
    unit_id = if standard, do: standard.id, else: newest.unit_id
    unit = Standard.known(of_series)

    {points, others} =
      entries
      |> Enum.map(&point(&1, unit_id, unit))
      |> Enum.split_with(&match?({:point, _}, &1))

    %__MODULE__{
      kind_id: newest.measure_kind_id,
      label: to_string(newest.measure_kind.label),
      unit_id: unit_id,
      unit_label: Standard.label(of_series),
      unit: unit,
      standard?: standard != nil,
      points: points |> Enum.map(&elem(&1, 1)) |> with_changes(),
      others: Enum.map(others, &elem(&1, 1))
    }
  end

  # A measurement is a point when it has the unit of the series, or a unit
  # that converts to it.
  defp point(entry, unit_id, unit) do
    measurement = entry.measurement
    own = loaded(measurement.unit)

    point = %Point{
      entry_id: entry.id,
      at: entry.happened_at,
      value: measurement.value,
      recorded: measurement.value,
      recorded_unit: Standard.label(own),
      note: entry.note
    }

    cond do
      measurement.unit_id == unit_id ->
        {:point, point}

      unit != nil ->
        with from when from != nil <- Standard.known(own),
             {:ok, value} <- Units.convert(measurement.value, from, unit) do
          {:point, %{point | value: value, converted?: true}}
        else
          _no -> {:other, point}
        end

      true ->
        {:other, point}
    end
  end

  defp with_changes(points) do
    {points, _last} =
      Enum.map_reduce(points, nil, fn
        point, nil ->
          {point, point}

        point, before ->
          {%{point | change: Decimal.sub(point.value, before.value), before: before.at}, point}
      end)

    points
  end

  defp loaded(%Ash.NotLoaded{}), do: nil
  defp loaded(value), do: value

  @doc """
  A series in the unit of another series of the same kind, so that two
  residents are on one scale: the weights of a litter, where one member
  was last weighed in kg and the others in g. `:error` when the unit of
  the series does not convert to the other one.
  """
  @spec like(t, t) :: {:ok, t} | :error
  def like(%__MODULE__{unit_id: unit_id} = series, %__MODULE__{unit_id: unit_id}),
    do: {:ok, series}

  def like(%__MODULE__{unit: %{} = from} = series, %__MODULE__{unit: %{} = to} = other) do
    if Units.convertible?(from, to) do
      points =
        for point <- series.points do
          {:ok, value} = Units.convert(point.value, from, to)
          %{point | value: value, converted?: true}
        end

      {:ok,
       %{
         series
         | unit_id: other.unit_id,
           unit_label: other.unit_label,
           unit: to,
           points: with_changes(points)
       }}
    else
      :error
    end
  end

  def like(%__MODULE__{}, %__MODULE__{}), do: :error

  @doc "The newest point of a series, or `nil` for a series with no point."
  @spec newest(t) :: Point.t() | nil
  def newest(%__MODULE__{points: points}), do: List.last(points)

  @doc """
  The series with only the points from an instant on. The change of the
  first point that stays is still from the point before it.
  """
  @spec since(t, DateTime.t() | nil) :: t
  def since(%__MODULE__{} = series, nil), do: series

  def since(%__MODULE__{} = series, %DateTime{} = from) do
    keep = fn point -> DateTime.compare(point.at, from) != :lt end
    %{series | points: Enum.filter(series.points, keep), others: Enum.filter(series.others, keep)}
  end

  @doc """
  The least and the greatest point of a series, or `nil` for a series with
  no point. Of two equal values, the newer one.
  """
  @spec extent(t) :: {Point.t(), Point.t()} | nil
  def extent(%__MODULE__{points: []}), do: nil

  def extent(%__MODULE__{points: points}) do
    {Enum.reduce(points, &if(Decimal.gt?(&1.value, &2.value), do: &2, else: &1)),
     Enum.reduce(points, &if(Decimal.lt?(&1.value, &2.value), do: &2, else: &1))}
  end
end
