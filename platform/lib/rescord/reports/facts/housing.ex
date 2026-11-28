defmodule Rescord.Reports.Facts.Housing do
  @moduledoc """
  The facts of the housing report: the tree of the locations of
  `Rescord.Locations.tree/1`, each with the residents and the groups that
  live there, and the residents in care that have no place.
  """

  @behaviour Rescord.Reports.Facts

  alias Rescord.Reports.Facts.{Places, Register}

  @impl true
  def read(_arguments, options, now) do
    today = Rescord.Accounts.local_date(options[:tenant], now)

    with {:ok, places} <- Places.read(options),
         {:ok, residents} <- Register.residents(today, options) do
      {:ok,
       %{
         tree: places.tree,
         today: today,
         unplaced: Enum.reject(residents, &Map.has_key?(places.homes, &1.id))
       }}
    end
  end
end
