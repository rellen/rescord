defmodule Rescord.Journal.EpisodeState do
  @moduledoc """
  Whether a condition of a resident is over (ADR 0083): `ongoing` while it
  has no last day, and `resolved` after. A fixed list (ADR 0025).
  """

  use Ash.Type.Enum, values: [:ongoing, :resolved]
end
