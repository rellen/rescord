defmodule Rescord.Residents.ResidentBreed do
  @moduledoc "A breed of a resident. A resident has one breed or more."

  use Rescord.Residents.Tie, table: "resident_breeds", value: :breed, list: Rescord.Lists.Breed
end
