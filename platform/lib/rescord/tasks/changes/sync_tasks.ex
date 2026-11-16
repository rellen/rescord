defmodule Rescord.Tasks.Changes.SyncTasks do
  @moduledoc """
  Keeps the tasks of a routine in step with it (ADR 0033), after the action
  on the routine and in the same transaction.

  ## Options

    * `drop?` - `true` cancels each task of the routine that is due and whose
      time is after now. The work that a member did, and the work that is
      late, stay.
    * `make?` - `true` makes the tasks of the routine from where the routine
      got to, up to its horizon.

  ## How it works

  The change reads the routine again with a lock, so two of these do not run
  for one routine at the same time. `generated_until` on the routine is the
  instant up to which its tasks exist. The change makes a task for each time
  of the pattern from that instant to the horizon, and moves the instant.
  When it drops the tasks that come, the instant goes back to now.

  A time that has a task of the routine gets no second one. So a task that
  a member finished ahead of its time stays the task of that time.

  One run makes 500 tasks at most. A routine with more than that to make
  gets the others in the next run.

  The horizon is the end of the day that is `days_ahead` days after today in
  the organisation. `days_ahead` is that of the routine, or else the setting
  of the organisation.

  The action passes the time in the argument `now` when it has one. The job
  does, and a test does.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias Rescord.Accounts
  alias Rescord.Tasks.{Pattern, Routine, Task}

  @most 500

  @impl true
  def change(changeset, opts, context) do
    Ash.Changeset.after_action(changeset, fn changeset, routine ->
      now = Ash.Changeset.get_argument(changeset, :now) || DateTime.utc_now()
      internal = [tenant: changeset.tenant, authorize?: false]
      # The schema, and not a record that a page read some time ago.
      organisation = Accounts.organisation_of(changeset.to_tenant)

      sync(routine, {organisation, now}, opts, internal, context.actor)
    end)
  end

  defp sync(routine, {organisation, now}, opts, internal, actor) do
    with {:ok, %Routine{} = locked} <- lock(routine, internal),
         {:ok, from} <- drop(locked, now, opts[:drop?], internal, actor),
         {:ok, until} <-
           make(locked, from, {organisation, now}, opts[:make?], internal, actor) do
      mark(locked, until, internal)
    else
      # The action removed the routine: it has no row to read, and no mark.
      {:ok, nil} -> drop_removed(routine, now, opts[:drop?], internal, actor)
      {:error, error} -> {:error, error}
    end
  end

  defp lock(routine, internal) do
    Routine
    |> Ash.Query.filter(id == ^routine.id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(internal)
  end

  defp drop_removed(routine, now, drop?, internal, actor) do
    with {:ok, _from} <- drop(routine, now, drop?, internal, actor), do: {:ok, routine}
  end

  # Returns the instant from which the tasks are to make.
  defp drop(routine, now, true, internal, actor) do
    coming =
      Task
      |> Ash.Query.filter(routine_id == ^routine.id and state == :due and due_at > ^now)
      |> Ash.read!(internal)

    Enum.reduce_while(coming, {:ok, now}, fn task, done ->
      case Ash.destroy(task, [action: :cancel, actor: actor] ++ internal) do
        :ok -> {:cont, done}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp drop(routine, now, _drop?, _internal, _actor),
    do: {:ok, routine.generated_until || now}

  # Returns the instant up to which the tasks exist now.
  defp make(%{paused: false} = routine, from, {organisation, now}, true, internal, actor) do
    # No task is for a time before now: not after a pause, and not after a
    # time when the job did not run.
    from = Enum.max([from, now], DateTime)
    until = horizon(routine, organisation, now)

    # A time that has a task is not made again: a member can finish a task
    # ahead of its time, and a change to the routine keeps that task.
    taken = taken(routine, from, internal)

    {times, more?} =
      routine
      |> instants(organisation, from, until)
      |> Enum.reject(&MapSet.member?(taken, DateTime.to_unix(&1)))
      |> Enum.split(@most)
      |> split()

    made =
      Enum.reduce_while(times, :ok, fn due_at, :ok ->
        case plan(routine, due_at, internal, actor) do
          {:ok, _task} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    cond do
      made != :ok -> made
      # The next run starts after the last task that this run made.
      more? -> {:ok, DateTime.add(List.last(times), 1, :second)}
      true -> {:ok, Enum.max([until, from], DateTime)}
    end
  end

  defp make(_routine, from, _time, _make?, _internal, _actor), do: {:ok, from}

  defp split({times, rest}), do: {times, rest != []}

  # The times from `from` that have a task of the routine, as seconds.
  defp taken(routine, from, internal) do
    Task
    |> Ash.Query.filter(routine_id == ^routine.id and due_at >= ^from)
    |> Ash.Query.select([:due_at])
    |> Ash.read!(internal)
    |> MapSet.new(&DateTime.to_unix(&1.due_at))
  end

  defp plan(routine, due_at, internal, actor) do
    Task
    |> Ash.Changeset.for_create(
      :generate,
      %{
        routine_id: routine.id,
        title: routine.title,
        note: routine.note,
        kind_id: routine.kind_id,
        assignee_id: routine.assignee_id,
        prescription_id: routine.prescription_id,
        due_at: due_at,
        resident_ids: routine.resident_ids,
        group_ids: routine.group_ids,
        location_ids: routine.location_ids
      },
      [actor: actor] ++ internal
    )
    |> Ash.create()
  end

  defp mark(routine, until, internal) do
    routine
    |> Ash.Changeset.for_update(:mark, %{until: until}, internal)
    |> Ash.update()
  end

  @doc """
  The end of the time for which a routine has tasks at `now`: the start of
  the day after the last day ahead, in the organisation of `tenant`.
  """
  def horizon(routine, tenant, %DateTime{} = now) do
    organisation = Accounts.organisation_of(tenant)
    days = routine.days_ahead || organisation.task_days_ahead
    last = organisation |> Accounts.local_date(now) |> Date.add(days)
    {_start, finish} = Accounts.day_range(organisation, last)
    finish
  end

  @doc """
  Each instant of a routine from `from` (included) to `until` (not
  included), in order: each time of each day of its pattern, in the time
  zone of the organisation of `tenant`.
  """
  def instants(routine, tenant, %DateTime{} = from, %DateTime{} = until) do
    if DateTime.compare(from, until) == :lt do
      organisation = Accounts.organisation_of(tenant)
      first = Accounts.local_date(organisation, from)
      last = Accounts.local_date(organisation, until)

      for date <- Pattern.dates(routine, first, last),
          time <- routine.times,
          instant = Accounts.local_instant(organisation, date, time),
          DateTime.compare(instant, from) != :lt and DateTime.compare(instant, until) == :lt,
          uniq: true do
        instant
      end
      |> Enum.sort(DateTime)
    else
      []
    end
  end
end
