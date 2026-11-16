defmodule Rescord.Inventory.Levels do
  @moduledoc """
  The level of the stock from the stock movements, with no database
  (`docs/domain.md`, section 5.8): Rescord stores no level.

  A place is the id of a location, or `nil` for no place in particular.

  ## Examples

      iex> movements = [
      ...>   %{lot_id: "a", location_id: "shed", quantity: Decimal.new(10)},
      ...>   %{lot_id: "a", location_id: "shed", quantity: Decimal.new(-4)},
      ...>   %{lot_id: "a", location_id: nil, quantity: Decimal.new(2)}
      ...> ]
      iex> levels = Rescord.Inventory.Levels.by_place(movements)
      iex> Decimal.to_string(levels[{"a", "shed"}])
      "6"
      iex> Decimal.to_string(Rescord.Inventory.Levels.of_lot(levels, "a"))
      "8"
  """

  @typedoc "The level of each lot in each place where it has a movement."
  @type t :: %{{lot_id :: String.t(), location_id :: String.t() | nil} => Decimal.t()}

  @zero Decimal.new(0)

  @doc "The sum of the movements of each lot in each place."
  @spec by_place(Enumerable.t()) :: t
  def by_place(movements) do
    Enum.reduce(movements, %{}, fn movement, levels ->
      Map.update(
        levels,
        {movement.lot_id, movement.location_id},
        movement.quantity,
        &Decimal.add(&1, movement.quantity)
      )
    end)
  end

  @doc """
  The places of each lot, each with its level, in one pass: a map from the
  id of a lot to its list of `{place, level}`, with the places that have a
  level that is not zero, in order.
  """
  @spec by_lot(t) :: %{String.t() => [{String.t() | nil, Decimal.t()}]}
  def by_lot(levels) do
    levels
    |> Enum.reject(fn {_key, level} -> Decimal.equal?(level, @zero) end)
    |> Enum.group_by(fn {{lot_id, _place}, _level} -> lot_id end, fn {{_lot, place}, level} ->
      {place, level}
    end)
    |> Map.new(fn {lot_id, places} -> {lot_id, Enum.sort(places)} end)
  end

  @doc "The level of one lot in one place."
  @spec at(t, String.t(), String.t() | nil) :: Decimal.t()
  def at(levels, lot_id, location_id), do: Map.get(levels, {lot_id, location_id}, @zero)

  @doc "The level of one lot in all its places."
  @spec of_lot(t, String.t()) :: Decimal.t()
  def of_lot(levels, lot_id) do
    for({{^lot_id, _place}, level} <- levels, do: level) |> sum()
  end

  @doc "The places of one lot that have a level that is not zero, each with its level."
  @spec places(t, String.t()) :: [{String.t() | nil, Decimal.t()}]
  def places(levels, lot_id) do
    for {{^lot_id, place}, level} <- levels, not Decimal.equal?(level, @zero), do: {place, level}
  end

  @doc "The sum of a list of quantities."
  @spec sum([Decimal.t()]) :: Decimal.t()
  def sum(quantities), do: Enum.reduce(quantities, @zero, &Decimal.add/2)
end
