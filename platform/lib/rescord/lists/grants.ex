defmodule Rescord.Lists.Grants do
  @moduledoc """
  What a role can do with the lists of an organisation (ADR 0024).

  Each role reads the lists. The power `:lists` adds a value, gives a
  local value a new name, and gives a measure kind its units and its
  standard unit and an item category its days before expiry (ADR 0040). The administrators have it. The base lists are outside the
  grants: only a root user writes one.
  """

  @behaviour Rescord.Accounts.Grants

  @impl true
  def reads, do: for(list <- Rescord.Lists.lists(), do: {list, :read, :all})

  @impl true
  def powers do
    %{
      lists:
        for(
          list <- Rescord.Lists.lists(),
          action <- [:add_shared, :add_local, :rename, :retire, :restore],
          do: {list, action, :all}
        ) ++
          [
            {Rescord.Lists.MeasureKind, :set_units, :all},
            {Rescord.Lists.MeasureKind, :set_standard_unit, :all},
            {Rescord.Lists.ItemCategory, :set_soon_days, :all}
          ]
    }
  end
end
