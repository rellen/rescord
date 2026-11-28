defmodule RescordWeb.HealthWords do
  @moduledoc """
  The words of the sanity checks (ADR 0114) on the pages of a root user:
  a level, the time of a run, and the line of `/root`.
  """

  @doc "The kind of `RescordWeb.CoreComponents.state/1`, and the word, of a level."
  @spec level(atom) :: {String.t(), String.t()}
  def level(:ok), do: {"ok", "Passes"}
  def level(:note), do: {"info", "Note"}
  def level(:fail), do: {"alert", "Fails"}
  def level(:unknown), do: {"none", "Could not run"}

  @doc "How often a check runs."
  @spec cadence(atom) :: String.t()
  def cadence(:hourly), do: "Each hour"
  def cadence(:daily), do: "Each day"
  def cadence(:weekly), do: "Each week"

  @doc "A time in UTC, such as 28 November 2026, 14:05 UTC."
  @spec time(DateTime.t() | nil) :: String.t()
  def time(nil), do: "never"
  def time(%DateTime{} = time), do: Calendar.strftime(time, "%-d %B %Y, %H:%M UTC")

  @doc "The line of the page `/root`, from `Rescord.Health.summary/1`."
  @spec summary(Rescord.Health.summary()) :: String.t()
  def summary(%{checked_at: nil}), do: "no check has run yet"
  def summary(%{fail: 0, unknown: 0, note: 0}), do: "each check passes"
  def summary(%{fail: 0, unknown: 0, note: 1}), do: "each check passes, with 1 note"
  def summary(%{fail: 0, unknown: 0, note: notes}), do: "each check passes, with #{notes} notes"

  def summary(%{fail: fails, unknown: unknown}) do
    [count(fails, "fails", "fail"), count(unknown, "could not run", "could not run")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", and ")
  end

  defp count(0, _one, _many), do: nil
  defp count(1, one, _many), do: "1 check #{one}"
  defp count(number, _one, many), do: "#{number} checks #{many}"
end
