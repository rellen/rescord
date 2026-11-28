defmodule Rescord.Reports.Facts.Movements do
  @moduledoc """
  The facts of the arrivals and the departures of a period: each resident
  that arrived from the first day to the last day, each one that left in
  those days, and how many the organisation had before the first day and at
  the end of the last one.

  The dates that the members gave decide, as in the register. So the number
  at the start, plus the arrivals, minus the departures, is the number at
  the end.
  """

  @behaviour Rescord.Reports.Facts

  require Ash.Query

  alias Rescord.Reports.Facts
  alias Rescord.Reports.Facts.Register
  alias Rescord.Residents
  alias Rescord.Residents.Resident

  @load [:name, :species_label, :arrival, :departure]

  @impl true
  def read(%{from: from, to: to}, options, now) do
    today = Rescord.Accounts.local_date(options[:tenant], now)

    cond do
      Date.compare(from, to) == :gt ->
        {:error, Facts.invalid(:to, "is before the first day")}

      Date.compare(to, today) == :gt ->
        {:error, Facts.invalid(:to, "is after today")}

      true ->
        with {:ok, arrived} <-
               Resident
               |> Ash.Query.filter(arrival.arrived_on >= ^from and arrival.arrived_on <= ^to)
               |> Ash.Query.sort(arrived_on: :asc, name: :asc, id: :asc)
               |> read(options),
             {:ok, left} <-
               Resident
               |> Ash.Query.filter(
                 departure.departed_on >= ^from and departure.departed_on <= ^to
               )
               |> read(options),
             {:ok, before} <- count(Date.add(from, -1), options),
             {:ok, after_it} <- count(to, options) do
          {:ok,
           %{
             from: from,
             to: to,
             arrived: arrived,
             left:
               Enum.sort_by(left, &{Date.to_gregorian_days(&1.departure.departed_on), &1.name}),
             at_start: before,
             at_end: after_it
           }}
        end
    end
  end

  defp read(query, options) do
    query |> Ash.Query.load(@load) |> then(&Residents.residents([query: &1] ++ options))
  end

  # How many residents the organisation had at the end of a day.
  defp count(on, options) do
    with {:ok, residents} <-
           Resident
           |> Register.in_care_on(on)
           |> Ash.Query.select([:id])
           |> then(&Residents.residents([query: &1] ++ options)) do
      {:ok, length(residents)}
    end
  end
end
