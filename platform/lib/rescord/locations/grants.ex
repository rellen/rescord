defmodule Rescord.Locations.Grants do
  @moduledoc """
  What a role can do with the locations of an organisation (ADR 0024).

  An administrator shapes the housing: adds a location, changes it, puts it
  inside another, and closes it. Each member reads the housing, and places
  and moves a resident or a group: that is the daily work.
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Locations.{Location, LocationParent, Placement}

  @member [
            {Location, [:read]},
            {LocationParent, [:read]},
            {Placement, [:read, :place, :move, :finish]}
          ]
          |> Enum.flat_map(fn {resource, actions} -> Enum.map(actions, &{resource, &1, :all}) end)

  @administrator [
                   {Location, [:add, :revise, :close]},
                   {LocationParent, [:put_inside, :take_out]}
                 ]
                 |> Enum.flat_map(fn {resource, actions} ->
                   Enum.map(actions, &{resource, &1, :all})
                 end)

  @impl true
  def grants, do: %{administrator: @member ++ @administrator, member: @member}
end
