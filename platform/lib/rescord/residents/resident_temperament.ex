defmodule Rescord.Residents.ResidentTemperament do
  @moduledoc "A temperament of a resident. A resident has zero temperaments or more."

  use Rescord.Residents.Tie,
    table: "resident_temperaments",
    value: :temperament,
    list: Rescord.Lists.Temperament
end
