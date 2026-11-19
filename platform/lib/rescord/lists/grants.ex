defmodule Rescord.Lists.Grants do
  @moduledoc """
  What a role can do with the lists of an organisation (ADR 0024).

  An administrator adds a value and gives a local value a new name. An
  administrator also gives a measure kind its units, and an item category
  its days before expiry. A member reads. The base lists are outside the
  grants: only a root user writes one.
  """

  @behaviour Rescord.Accounts.Grants

  @impl true
  def grants do
    lists = Rescord.Lists.lists()

    %{
      administrator:
        for(
          list <- lists,
          action <- [:read, :add_shared, :add_local, :rename, :retire, :restore],
          do: {list, action, :all}
        ) ++
          [
            {Rescord.Lists.MeasureKind, :set_units, :all},
            {Rescord.Lists.ItemCategory, :set_soon_days, :all}
          ],
      member: for(list <- lists, do: {list, :read, :all})
    }
  end
end
