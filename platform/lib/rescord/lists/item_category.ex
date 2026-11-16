defmodule Rescord.Lists.ItemCategory do
  @moduledoc "The values of the dimension `item category` that one organisation uses."

  use Rescord.Lists.OrganisationList,
    table: "item_categories",
    base: Rescord.Lists.Base.ItemCategory
end
