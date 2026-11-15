defmodule Rescord.Residents.ArrivalKind do
  @moduledoc "How a resident came to the organisation. A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:surrender, :stray, :seizure, :born_in_care, :transfer_in]
end
