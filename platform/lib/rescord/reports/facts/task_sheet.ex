defmodule Rescord.Reports.Facts.TaskSheet do
  @moduledoc """
  The facts of the tasks of one day: the tasks that are due on that day, in
  the order of their times. For today, the tasks of an earlier day that are
  still due are there too: they are late.
  """

  @behaviour Rescord.Reports.Facts

  alias Rescord.{Accounts, Tasks}
  alias Rescord.Reports.Facts

  @impl true
  def read(arguments, options, now) do
    today = Accounts.local_date(options[:tenant], now)

    with {:ok, on} <- Facts.day(arguments[:on], options, now),
         {:ok, tasks} <- Tasks.day(on, options),
         {:ok, late} <- late(on == today, on, options, now),
         {:ok, members} <- Accounts.members([load: [:email]] ++ options) do
      {:ok,
       %{
         on: on,
         now: now,
         late: late,
         tasks: tasks,
         members: Map.new(members, &{&1.user_id, to_string(&1.email)})
       }}
    end
  end

  # The tasks of an earlier day that are still due.
  defp late(false, _on, _options, _now), do: {:ok, []}

  defp late(true, on, options, now) do
    {start, _next} = Accounts.day_range(options[:tenant], on)

    with {:ok, overdue} <- Tasks.overdue(now, options) do
      {:ok, Enum.filter(overdue, &(DateTime.compare(&1.due_at, start) == :lt))}
    end
  end
end
