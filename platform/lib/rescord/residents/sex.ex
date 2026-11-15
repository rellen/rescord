defmodule Rescord.Residents.Sex do
  @moduledoc "The sex of a resident. A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:female, :male, :unknown]
end
