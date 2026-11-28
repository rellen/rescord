defmodule RescordWeb.ReportWords.TaskSheet do
  @moduledoc "The words of the tasks of a day (`Rescord.Reports.Facts.TaskSheet`)."

  import RescordWeb.ReportWords

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.{ResidentWords, TaskWords}

  def data(facts) do
    %{
      frame: frame(facts, "Tasks of the day", TaskWords.day(facts.on)),
      late: Enum.map(facts.late, &row(&1, facts, :late)),
      tasks: Enum.map(facts.tasks, &row(&1, facts, :day))
    }
  end

  defp row(task, facts, part) do
    local = Accounts.local_time(facts.organisation, task.due_at)

    %{
      # A late task says its day too.
      time:
        if(part == :late,
          do: "#{ResidentWords.date(DateTime.to_date(local))}, #{TaskWords.time(local)}",
          else: TaskWords.time(local)
        ),
      title: task.title,
      kind: label(task.kind),
      for:
        case Tasks.subject_names(task) do
          [] -> nil
          names -> Enum.join(names, ", ")
        end,
      who: who(task, facts.members),
      note: text(task.note),
      done: task.state == :done,
      state: state(task)
    }
  end

  defp who(%{assignee_ids: []}, _members), do: "Anybody"

  defp who(%{assignee_ids: ids}, members),
    do: Enum.map_join(ids, ", ", &Map.get(members, &1, "A person who is not a member now"))

  # The words of a task that is not open, or `nil`.
  defp state(%{state: :done}), do: TaskWords.phase(:done)

  defp state(%{state: :skipped} = task) do
    case text(task.skip_reason) do
      nil -> TaskWords.phase(:skipped)
      reason -> "#{TaskWords.phase(:skipped)}: #{reason}"
    end
  end

  defp state(_task), do: nil
end
