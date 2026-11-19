defmodule Rescord.Lists.ItemCategory do
  @moduledoc """
  The values of the dimension `item category` that one organisation uses.

  A category says how many days before its expiry date a lot of it expires
  soon, for example 14 days for food and 60 days for a medication (the
  maintainer, 18 November 2026). A category with no number uses 30 days.
  """

  use Rescord.Lists.OrganisationList,
    table: "item_categories",
    base: Rescord.Lists.Base.ItemCategory

  attributes do
    attribute :soon_days, :integer do
      public? true
      constraints min: 0, max: 3650
      description "The days before its expiry date in which a lot expires soon. None: 30"
    end
  end

  actions do
    update :set_soon_days do
      description "Gives the days before its expiry date in which a lot of this category expires soon"
      accept [:soon_days]
    end
  end
end
