defmodule Rescord.ClockFixtures do
  @moduledoc """
  Keeps a test that reads the clock away from an edge of time: the
  midnight of an organisation, the start of a UTC day, or the start of a
  window of a rate limit. Code such as a tool of Ruby reads the clock
  itself, so a test that compares its day with the day that the test read
  fails when the day changes in between, as it does on CI at 14:00 UTC for
  an organisation in Brisbane.

  When the edge is less than the margin away, the helper waits until it
  has passed, so the test runs at the start of the next day or window.
  It waits for at most the margin.
  """

  # Test support may use any boundary, and any test may use it (ADR 0009).
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias Rescord.Accounts

  @margin :timer.seconds(15)

  @doc """
  Waits past the next midnight of the organisation when it is less than
  `margin` milliseconds away.
  """
  @spec clear_of_midnight(Ash.Resource.record(), non_neg_integer) :: :ok
  def clear_of_midnight(organisation, margin \\ @margin) do
    tomorrow = organisation |> Accounts.today() |> Date.add(1) |> Date.to_iso8601()
    {:ok, midnight} = Accounts.local_instant(organisation, tomorrow <> "T00:00")
    wait_past(DateTime.diff(midnight, DateTime.utc_now(), :millisecond), margin)
  end

  @doc """
  Waits past the next edge of a window of `scale` milliseconds of the
  system clock when it is less than `margin` milliseconds away. A fixed
  window of a rate limit starts at such an edge, and a UTC day and month
  start at an edge of `:timer.hours(24)`.
  """
  @spec clear_of_edge(pos_integer, non_neg_integer) :: :ok
  def clear_of_edge(scale, margin \\ @margin) do
    wait_past(scale - rem(System.system_time(:millisecond), scale), margin)
  end

  defp wait_past(left, margin) when left < margin, do: Process.sleep(max(left, 0) + 100)
  defp wait_past(_left, _margin), do: :ok
end
