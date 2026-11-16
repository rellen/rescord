defmodule Rescord.Journal.Route do
  @moduledoc "How a resident takes a medication. A fixed list (ADR 0025)."

  use Ash.Type.Enum, values: [:oral, :topical, :injection, :eye, :ear, :other]
end
