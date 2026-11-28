defmodule Rescord.Health.Checks.Clock do
  @moduledoc """
  C12 of issue 38: the clock of the server against the clock of
  PostgreSQL. Rescord writes the times of the history with the clock of
  the database and reads them with the clock of the server, so a skew
  moves what a page shows as now, the tasks of a day, and the times of a
  sign-in link. The count is the skew in whole seconds.
  """

  use Rescord.Health.Check

  @note_seconds 2
  @fail_seconds 30

  @impl true
  def name, do: :clock
  @impl true
  def scope, do: :server
  @impl true
  def cadence, do: :hourly
  @impl true
  def title, do: "The clock of the server against the clock of the database"

  @impl true
  def explain,
    do:
      "The two clocks differ by the count, in seconds. Turn on a time service (NTP) " <>
        "on the machine of the server and on the machine of the database."

  @impl true
  def run(_context) do
    before = System.os_time(:microsecond)
    %{rows: [[database]]} = Rescord.Repo.query!("select clock_timestamp()", [])
    later = System.os_time(:microsecond)

    server = div(before + later, 2)
    skew = abs(DateTime.to_unix(database, :microsecond) - server) |> div(1_000_000)
    level(skew)
  end

  @doc "The finding for a skew of `seconds`."
  @spec level(non_neg_integer) :: Rescord.Health.Check.finding()
  def level(seconds) when seconds > @fail_seconds, do: %{level: :fail, count: seconds, ids: []}
  def level(seconds) when seconds > @note_seconds, do: %{level: :note, count: seconds, ids: []}
  def level(_seconds), do: ok()
end
