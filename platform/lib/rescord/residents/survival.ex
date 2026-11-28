defmodule Rescord.Residents.Survival do
  @moduledoc """
  How long the residents stay (ADR 0124): the share of a group of stays
  still in care against the days since the arrival, by the method of
  Kaplan and Meier. A stay that goes on counts as in care up to its days so
  far, and then leaves the count without a departure, so a long stay that
  goes on is not lost and does not count as ended.

  A stay is `{days, ended?}`: its days from the arrival to the departure,
  or to today, and whether it ended. The shares are exact fractions until
  the end, so a half is a half.

  This module reads nothing. It is pure: the same stays give the same
  curve.
  """

  @doc """
  The curve of some stays: `{days, share}` at the start and at each day on
  which a stay ended, the share a `Decimal` from 1 down, rounded to four
  places.

      iex> Rescord.Residents.Survival.curve([{2, true}, {4, true}, {4, false}, {6, true}])
      [{0, Decimal.new("1")}, {2, Decimal.new("0.75")}, {4, Decimal.new("0.5")}, {6, Decimal.new("0")}]

      iex> Rescord.Residents.Survival.curve([])
      [{0, Decimal.new("1")}]
  """
  @spec curve([{non_neg_integer, boolean}]) :: [{non_neg_integer, Decimal.t()}]
  def curve(stays) do
    for {days, {numerator, denominator}} <- fractions(stays),
        do:
          {days, numerator |> Decimal.div(denominator) |> Decimal.round(4) |> Decimal.normalize()}
  end

  @doc """
  The first day by which the share of some stays still in care was at most
  `share` of the whole, such as a half; `nil` when it never was.

      iex> stays = [{2, true}, {4, true}, {4, false}, {6, true}]
      iex> Rescord.Residents.Survival.day_when(stays, {1, 2})
      4
      iex> Rescord.Residents.Survival.day_when(stays, {1, 4})
      6
      iex> Rescord.Residents.Survival.day_when([{3, false}], {1, 2})
      nil
  """
  @spec day_when([{non_neg_integer, boolean}], {pos_integer, pos_integer}) ::
          non_neg_integer | nil
  def day_when(stays, {part, whole}) do
    Enum.find_value(fractions(stays), fn {days, {numerator, denominator}} ->
      if numerator * whole <= part * denominator, do: days
    end)
  end

  # The share in care as an exact fraction at the start and after each day
  # on which a stay ended: the product of (at risk - ended) / at risk.
  defp fractions(stays) do
    ended =
      for({days, true} <- stays, do: days)
      |> Enum.frequencies()
      |> Enum.sort()

    {steps, _} =
      Enum.map_reduce(ended, {1, 1}, fn {day, count}, {numerator, denominator} ->
        at_risk = Enum.count(stays, fn {days, _} -> days >= day end)
        share = {numerator * (at_risk - count), denominator * at_risk}
        {{day, share}, share}
      end)

    [{0, {1, 1}} | steps]
  end
end
