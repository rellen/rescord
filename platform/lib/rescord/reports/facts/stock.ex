defmodule Rescord.Reports.Facts.Stock do
  @moduledoc """
  The facts of the stock report: the stock of each item as
  `Rescord.Inventory.stock/1` gives it, and the path of each location, for
  the place of a lot.
  """

  @behaviour Rescord.Reports.Facts

  alias Rescord.Inventory
  alias Rescord.Reports.Facts.Places

  @impl true
  def read(_arguments, options, now) do
    with {:ok, stock} <- Inventory.stock(options),
         {:ok, places} <- Places.read(options) do
      {:ok,
       %{
         stock: stock,
         paths: places.paths,
         today: Rescord.Accounts.local_date(options[:tenant], now)
       }}
    end
  end
end
