defmodule Rescord.Reports.Facts.Register do
  @moduledoc """
  The facts of the register of the residents on a day.

  A resident is in the register of a day when its arrival is on or before
  that day, and it has no departure on or before that day: the dates that
  the members gave decide, so that the register agrees with the report of
  the arrivals and the departures. Its facts are the ones of now.

  For a past day, the place of each resident and whether it was away are
  the ones that the records held at the end of that day (ADR 0012).
  """

  @behaviour Rescord.Reports.Facts

  require Ash.Query

  alias Rescord.Reports.Facts
  alias Rescord.Residents
  alias Rescord.Residents.Resident

  @load [
    :name,
    :species_label,
    :desex_status,
    :arrival,
    resident_breeds: [breed: [:label]],
    identifiers: [kind: [:label]]
  ]

  @impl true
  def read(arguments, options, now) do
    with {:ok, on} <- Facts.day(arguments[:on], options, now, past_only?: true),
         past = Facts.past(on, options, now),
         {:ok, residents} <- residents(on, options),
         {:ok, recorded} <- Residents.residents([load: [:status]] ++ past ++ options),
         {:ok, places} <- Facts.Places.read(past ++ options) do
      status = Map.new(recorded, &{&1.id, &1.status})

      rows =
        for resident <- residents do
          %{
            resident: resident,
            # A resident that the records did not hold yet was in care.
            away?: Map.get(status, resident.id) == :away,
            homes: Map.get(places.homes, resident.id, [])
          }
        end

      {:ok, %{on: on, today: Rescord.Accounts.local_date(options[:tenant], now), rows: rows}}
    end
  end

  @doc "The residents that the organisation had at the end of a day, in the order of their names."
  def residents(%Date{} = on, options) do
    Resident
    |> in_care_on(on)
    |> Ash.Query.load(@load)
    |> Ash.Query.sort(name: :asc, id: :asc)
    |> then(&Residents.residents([query: &1] ++ options))
  end

  @doc "The filter of the residents that the organisation had at the end of a day."
  def in_care_on(query, %Date{} = on) do
    Ash.Query.filter(
      query,
      arrival.arrived_on <= ^on and
        (is_nil(departure.departed_on) or departure.departed_on > ^on)
    )
  end
end
