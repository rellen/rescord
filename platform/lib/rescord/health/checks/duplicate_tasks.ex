defmodule Rescord.Health.Checks.DuplicateTasks do
  @moduledoc """
  C18 of issue 38: two tasks of one routine for one time. The job of the
  tasks makes one task for each time of a routine, and no unique index
  holds it, because a cancelled task keeps its row and its time when a
  pause makes it again (ADR 0033). So two tasks of a routine at the same
  `due_at` that are not cancelled ask the members to do one thing twice.

  The ids are those of the tasks.
  """

  use Rescord.Health.Check

  @impl true
  def name, do: :duplicate_tasks
  @impl true
  def scope, do: :organisation
  @impl true
  def cadence, do: :daily
  @impl true
  def title, do: "Two tasks of a routine for one time"

  @impl true
  def explain,
    do:
      "A routine has two tasks for the same time, so the members see the work twice and a " <>
        "dose may be given twice. Cancel one of them on the page of the tasks, and report it."

  @impl true
  def run(context) do
    tasks = table(context, "tasks")

    """
    select t.id from #{tasks} t
    where t.routine_id is not null and t.archived_at is null
      and exists (
        select 1 from #{tasks} o
        where o.routine_id = t.routine_id and o.due_at = t.due_at and o.id <> t.id
          and o.archived_at is null)
    """
    |> query()
    |> found(:fail)
  end
end
