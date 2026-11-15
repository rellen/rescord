defmodule Rescord.Residents.Status do
  @moduledoc "Where a resident is in its stay (docs/domain.md, section 5.2). A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:expected, :in_care, :away, :left]
end
