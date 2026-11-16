defmodule Rescord.Residents.KinRole do
  @moduledoc "What a parent is to its young: the mother or the father. A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:mother, :father]
end
