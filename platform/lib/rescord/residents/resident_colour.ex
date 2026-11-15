defmodule Rescord.Residents.ResidentColour do
  @moduledoc "A colour of a resident. A resident has one colour or more."

  use Rescord.Residents.Tie, table: "resident_colours", value: :colour, list: Rescord.Lists.Colour
end
