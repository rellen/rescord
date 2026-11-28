defmodule Rescord.Residents.Census do
  @moduledoc """
  The counts of the stays of `Rescord.Residents.stays/1` over time
  (ADR 0117): how many residents were in care at the end of each day, and
  how many arrived and left in each week. A resident is in care at the end
  of a day when it arrived on that day or before, and has not left by then,
  as `Rescord.Reports.Facts.Register.in_care_on/2` says.

  This module reads nothing. It is pure: the same stays give the same
  counts.
  """

  @doc """
  The residents in care at the end of each day from `first` to `last`.

      iex> stays = [
      ...>   %{arrived_on: ~D[2026-11-01], departed_on: ~D[2026-11-03]},
      ...>   %{arrived_on: ~D[2026-11-02], departed_on: nil},
      ...>   %{arrived_on: ~D[2026-10-01], departed_on: ~D[2026-10-05]}
      ...> ]
      iex> Rescord.Residents.Census.by_day(stays, ~D[2026-11-01], ~D[2026-11-04])
      [{~D[2026-11-01], 1}, {~D[2026-11-02], 2}, {~D[2026-11-03], 1}, {~D[2026-11-04], 1}]
  """
  @spec by_day([map], Date.t(), Date.t()) :: [{Date.t(), non_neg_integer}]
  def by_day(stays, %Date{} = first, %Date{} = last) do
    # A change of the count on each day: one more on the day of an arrival,
    # one less on the day of a departure. A stay of before the first day
    # starts the count.
    {start, changes} =
      Enum.reduce(stays, {0, %{}}, fn stay, {start, changes} ->
        cond do
          stay.departed_on && Date.compare(stay.departed_on, first) != :gt ->
            {start, changes}

          Date.compare(stay.arrived_on, first) != :gt ->
            {start + 1, leave(changes, stay)}

          true ->
            {start, changes |> Map.update(stay.arrived_on, 1, &(&1 + 1)) |> leave(stay)}
        end
      end)

    {counts, _} =
      Enum.map_reduce(Date.range(first, last), start, fn date, count ->
        count = if date == first, do: count, else: count + Map.get(changes, date, 0)
        {{date, count}, count}
      end)

    counts
  end

  defp leave(changes, %{departed_on: nil}), do: changes
  defp leave(changes, %{departed_on: on}), do: Map.update(changes, on, -1, &(&1 - 1))

  @doc """
  The arrivals and the departures of each week that starts on one of
  `mondays`, as `{monday, arrivals, departures}`.

      iex> stays = [
      ...>   %{arrived_on: ~D[2026-11-17], departed_on: ~D[2026-11-24]},
      ...>   %{arrived_on: ~D[2026-11-22], departed_on: nil}
      ...> ]
      iex> Rescord.Residents.Census.by_week(stays, [~D[2026-11-16], ~D[2026-11-23]])
      [{~D[2026-11-16], 2, 0}, {~D[2026-11-23], 0, 1}]
  """
  @spec by_week([map], [Date.t()]) :: [{Date.t(), non_neg_integer, non_neg_integer}]
  def by_week(stays, mondays) do
    arrivals = Enum.frequencies_by(stays, &Date.beginning_of_week(&1.arrived_on))

    departures =
      for %{departed_on: %Date{} = on} <- stays,
          reduce: %{},
          do: (acc -> Map.update(acc, Date.beginning_of_week(on), 1, &(&1 + 1)))

    for monday <- mondays,
        do: {monday, Map.get(arrivals, monday, 0), Map.get(departures, monday, 0)}
  end
end
