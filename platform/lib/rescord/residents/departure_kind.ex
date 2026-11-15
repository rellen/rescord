defmodule Rescord.Residents.DepartureKind do
  @moduledoc "How a resident left the organisation. A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:death, :release, :transfer_out]
end
