defmodule Rescord.Residents.DesexStatus do
  @moduledoc "Whether a resident is desexed. A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:entire, :desexed, :unknown]
end
