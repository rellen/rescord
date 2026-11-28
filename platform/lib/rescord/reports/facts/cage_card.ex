defmodule Rescord.Reports.Facts.CageCard do
  @moduledoc """
  The facts of the cage card of a resident: its picture, its facts, where it
  lives, its newest measurements, and the routines that are for it or for a
  group of it, and that run today.
  """

  @behaviour Rescord.Reports.Facts

  alias Rescord.{Journal, Residents, Tasks}
  alias Rescord.Reports.Facts.{Places, ResidentRecord}

  @impl true
  def read(%{resident_id: id}, options, now) do
    today = Rescord.Accounts.local_date(options[:tenant], now)

    with {:ok, resident} <- ResidentRecord.resident(id, options),
         {:ok, places} <- Places.read(options),
         {:ok, measurements} <- Journal.latest_measurements(id, options),
         {:ok, routines} <- Tasks.routines_with_facts(now, options),
         {:ok, profile} <- ResidentRecord.profile(id, options, :display) do
      relations = Residents.relations(id, options)
      group_ids = for {_membership, group} <- (relations && relations.groups) || [], do: group.id

      {:ok,
       %{
         resident: resident,
         today: today,
         homes: Map.get(places.homes, id, []),
         measurements: measurements,
         routines: Enum.filter(routines, &for_resident?(&1, id, group_ids, today)),
         profile: profile && profile.file,
         files: if(profile, do: %{profile.file => profile.bytes}, else: %{})
       }}
    end
  end

  defp for_resident?(routine, id, group_ids, today) do
    not routine.paused and
      Date.compare(routine.starts_on, today) != :gt and
      (is_nil(routine.ends_on) or Date.compare(routine.ends_on, today) != :lt) and
      (id in routine.resident_ids or Enum.any?(group_ids, &(&1 in routine.group_ids)))
  end
end
