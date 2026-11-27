defmodule RescordWeb.InventoryWords do
  @moduledoc """
  The words that a page uses for the inventory: a quantity with its unit, a
  lot, a stock movement, the expiry of a lot and the state of an item. A
  page never shows the atom of a value.
  """

  alias RescordWeb.JournalWords

  @expiry [
    expired: {"Past its expiry date", "alert"},
    soon: {"Expires soon", "info"},
    later: {"In date", "ok"},
    none: {"No expiry date", "none"}
  ]

  @faults [
    below_zero: {"Count the stock", "alert"},
    short: {"Order more", "alert"},
    expired: {"Has stock past its expiry date", "alert"},
    soon: {"Has stock that expires soon", "info"}
  ]

  @movements [
    received: "Received",
    used: "Used",
    moved: "Moved",
    discarded: "Thrown out",
    counted: "Counted"
  ]

  @doc "A quantity with the unit of its item: `10.5 kg`, or `10.5` for an item with no unit."
  def quantity(%Decimal{} = quantity, item) do
    case unit(item) do
      nil -> JournalWords.number(quantity)
      unit -> "#{JournalWords.number(quantity)} #{unit}"
    end
  end

  @doc "A quantity as the value of a field of a form: `10.5`, with no comma."
  def plain(%Decimal{} = quantity),
    do: quantity |> Decimal.normalize() |> Decimal.to_string(:normal)

  @doc "The unit of an item in words, or `nil`."
  def unit(%{unit: %{label: label}}) when not is_nil(label), do: to_string(label)
  def unit(_item), do: nil

  @doc "The name of a lot: its code, or words for a lot with none."
  def lot(%{code: code}) when is_binary(code), do: "Lot #{code}"
  def lot(_lot), do: "A lot with no code"

  @doc "The words for where a lot is with its expiry date."
  def expiry(state), do: @expiry |> Keyword.fetch!(state) |> elem(0)

  @doc "The kind of state that `<.state>` draws for the expiry of a lot."
  def expiry_kind(state), do: @expiry |> Keyword.fetch!(state) |> elem(1)

  @doc "The states of the expiry that have words, for the test that holds them."
  def expiries, do: Keyword.keys(@expiry)

  @doc """
  What a stock movement was, in words. A move says its direction, and a
  count says what it found.
  """
  def movement(%{kind: :moved, quantity: quantity}),
    do: if(Decimal.negative?(quantity), do: "Moved out", else: "Moved in")

  def movement(%{kind: :counted, quantity: quantity}) do
    cond do
      Decimal.negative?(quantity) -> "Counted: less than the record"
      Decimal.positive?(quantity) -> "Counted: more than the record"
      true -> "Counted: the same as the record"
    end
  end

  def movement(%{kind: kind}), do: Keyword.fetch!(@movements, kind)

  @doc "The kinds of movement that have words, for the test that holds them."
  def movements, do: Keyword.keys(@movements)

  @doc "The change of a stock movement with its sign: `+5`, `−4`, `0`."
  def change(%Decimal{} = quantity) do
    cond do
      Decimal.negative?(quantity) -> "−" <> JournalWords.number(Decimal.abs(quantity))
      Decimal.positive?(quantity) -> "+" <> JournalWords.number(quantity)
      true -> "0"
    end
  end

  @doc """
  The states of the stock of an item, each as `{words, kind}`: what a member
  must know first is first. An item with stock and no fault is `In stock`.
  """
  def states(stock) do
    case Rescord.Inventory.faults(stock) do
      [] ->
        if Decimal.compare(stock.level, Decimal.new(0)) == :gt,
          do: [{"In stock", "ok"}],
          else: [{"None in stock", "none"}]

      faults ->
        Enum.map(faults, &fault/1)
    end
  end

  @doc "A fault of the stock of an item (`Rescord.Inventory.faults/1`), as `{words, kind}`."
  def fault(fault), do: Keyword.fetch!(@faults, fault)

  @doc "The faults that have words, for the test that holds them."
  def faults, do: Keyword.keys(@faults)
end
