defmodule Rescord.Locations.Grants do
  @moduledoc """
  What a role can do with the locations of an organisation (ADR 0024).

  Each role reads the housing. The power `:placements` places and moves a
  resident or a group: that is the daily work of each member. The power
  `:locations` shapes the housing: it adds a location, changes it, puts it
  inside another, and closes it. Only the administrators have it at first
  (ADR 0040).
  """

  @behaviour Rescord.Accounts.Grants

  alias Rescord.Locations.{Location, LocationParent, Placement}

  @impl true
  def reads,
    do: for(resource <- [Location, LocationParent, Placement], do: {resource, :read, :all})

  @impl true
  def powers do
    %{
      placements: for(action <- [:place, :move, :finish], do: {Placement, action, :all}),
      locations:
        for(action <- [:add, :revise, :close], do: {Location, action, :all}) ++
          for(action <- [:put_inside, :take_out], do: {LocationParent, action, :all})
    }
  end
end
