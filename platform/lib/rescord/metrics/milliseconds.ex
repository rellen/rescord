defmodule Rescord.Metrics.Milliseconds do
  @moduledoc """
  The buckets of a time in milliseconds, for the reporter (ADR 0077): from
  1 ms to 30 s, in 14 steps. The default of Peep has about 100 buckets for
  each series, which is more than a small server needs to send.
  """

  use Peep.Buckets.Custom,
    buckets: [1, 2, 5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000]
end
