defmodule Rescord.Tasks do
  @moduledoc """
  The tasks of an organisation: the pieces of work that its members do for a
  resident, a group or a location (`docs/domain.md`, section 5.7, and
  ADR 0032).

  `day/2` gives the tasks of one day in the time zone of the organisation,
  and `phase/2` says where a task is: overdue, due, done or skipped.
  """

  use Ash.Domain,
    otp_app: :rescord,
    extensions: [AshBoundary, AshPaperTrail.Domain]

  require Ash.Query
  require Logger

  alias Rescord.Tasks.Changes.SyncTasks
  alias Rescord.Tasks.{Routine, Task, TaskSubject}

  boundary do
    deps [
      Rescord,
      Rescord.Accounts,
      Rescord.Lists,
      Rescord.Residents,
      Rescord.Locations,
      Rescord.Journal
    ]
  end

  paper_trail do
    include_versions? true
  end

  resources do
    resource Rescord.Tasks.Task do
      define :tasks, action: :read
      define :task, action: :read, get_by: [:id], not_found_error?: false
      define :plan_task, action: :plan
      define :revise_task, action: :revise
      define :take_task, action: :take
      define :give_task, action: :give
      define :complete_task, action: :complete
      define :skip_task, action: :skip
      define :reopen_task, action: :reopen
      define :cancel_task, action: :cancel
    end

    resource Rescord.Tasks.TaskSubject

    resource Rescord.Tasks.Routine do
      define :routines, action: :read
      define :routine, action: :read, get_by: [:id], not_found_error?: false
      define :start_routine, action: :start
      define :revise_routine, action: :revise
      define :pause_routine, action: :pause
      define :resume_routine, action: :resume
      define :remove_routine, action: :remove
    end
  end

  # What a page shows of a task: its kind, and the name of each subject.
  @facts [
    kind: [:label],
    subjects: [resident: [:name], group: [members: [resident: [:name]]], location: []]
  ]

  @doc """
  The tasks that are due on one day of the organisation, in the order of
  their times. `date` is a date in the time zone of the organisation, and
  `opts` names the organisation in `:tenant`.
  """
  def day(%Date{} = date, opts \\ []) do
    {from, to} = Rescord.Accounts.day_range(opts[:tenant], date)

    Task
    |> Ash.Query.filter(due_at >= ^from and due_at < ^to)
    |> Ash.Query.sort(due_at: :asc, title: :asc)
    |> Ash.Query.load(@facts)
    |> Ash.read(opts)
  end

  @doc "The tasks that are due and whose time is before `now`, the oldest first."
  def overdue(%DateTime{} = now, opts \\ []) do
    Task
    |> Ash.Query.filter(state == :due and due_at < ^now)
    |> Ash.Query.sort(due_at: :asc)
    |> Ash.Query.load(@facts)
    |> Ash.read(opts)
  end

  @doc "One task with its kind and its subjects, or `nil`."
  def task_with_facts(id, opts \\ []), do: task(id, Keyword.put(opts, :load, @facts))

  @doc """
  Where a task is at an instant: `:overdue` for a task that is due and whose
  time is before the instant, and its state in each other case.
  """
  @spec phase(map, DateTime.t()) :: :overdue | :due | :done | :skipped
  def phase(%{state: :due, due_at: due_at}, %DateTime{} = now) do
    if DateTime.compare(due_at, now) == :lt, do: :overdue, else: :due
  end

  def phase(%{state: state}, _now), do: state

  @doc "The names of what a task is for, in one list. Empty for a task with no subject."
  def subject_names(%Task{subjects: subjects}) when is_list(subjects) do
    for subject <- subjects, name = subject_name(subject), not is_nil(name), do: name
  end

  defp subject_name(%TaskSubject{resident: %{} = resident})
       when not is_struct(resident, Ash.NotLoaded),
       do: resident.name || "A resident with no name"

  defp subject_name(%TaskSubject{group: %{members: _} = group}),
    do: Rescord.Residents.group_name(group)

  defp subject_name(%TaskSubject{location: %{name: name}}), do: name
  defp subject_name(_subject), do: nil

  @doc """
  The routines of the organisation with the kind of each, in the order of
  their titles. Each one has the metadata `:next`: the time of its first
  task that is due after `now`, or `nil`.
  """
  def routines_with_facts(now \\ DateTime.utc_now(), opts \\ []) do
    with {:ok, routines} <-
           Routine
           |> Ash.Query.sort(title: :asc, id: :asc)
           |> Ash.Query.load(kind: [:label])
           |> Ash.read(opts),
         {:ok, coming} <-
           Task
           |> Ash.Query.filter(not is_nil(routine_id) and state == :due and due_at >= ^now)
           |> Ash.Query.sort(due_at: :asc)
           |> Ash.Query.select([:routine_id, :due_at])
           |> Ash.read(opts) do
      # The first task of each routine is its next one: the list is in order.
      next = coming |> Enum.uniq_by(& &1.routine_id) |> Map.new(&{&1.routine_id, &1.due_at})

      {:ok, Enum.map(routines, &Ash.Resource.put_metadata(&1, :next, next[&1.id]))}
    end
  end

  @doc "The time of the next task of a routine that `routines_with_facts/2` read, or `nil`."
  def next_task_at(%Routine{} = routine), do: Ash.Resource.get_metadata(routine, :next)

  @doc """
  Makes the tasks of each routine of an organisation up to its horizon, as
  of `now`. The job calls this each hour. It asks no policy: no person is
  there. Returns the number of routines that got tasks.

  A fault in one routine does not stop the others. The log names the
  routine and the fault.
  """
  @spec generate(Ash.Resource.record(), DateTime.t()) :: non_neg_integer
  def generate(organisation, now \\ DateTime.utc_now()) do
    internal = [tenant: organisation, authorize?: false]

    Routine
    |> Ash.Query.filter(paused == false)
    |> Ash.read!(internal)
    |> Enum.reject(&up_to_date?(&1, organisation, now))
    |> Enum.count(fn routine ->
      case routine
           |> Ash.Changeset.for_update(:generate, %{now: now}, internal)
           |> Ash.update() do
        {:ok, _routine} ->
          true

        {:error, error} ->
          Logger.error("The routine #{routine.id} got no tasks: #{Exception.message(error)}")
          false
      end
    end)
  end

  # A routine whose tasks exist up to its horizon needs no write.
  defp up_to_date?(%{generated_until: nil}, _organisation, _now), do: false

  defp up_to_date?(routine, organisation, now) do
    DateTime.compare(routine.generated_until, SyncTasks.horizon(routine, organisation, now)) !=
      :lt
  end

  @doc """
  Whether a role can run an action of a routine at all. A page asks this to
  decide what to show. The policy decides when the action runs.
  """
  @spec role_can_routine?(atom | nil, atom) :: boolean
  def role_can_routine?(role, action), do: Rescord.Accounts.granted?(role, Routine, action)

  @doc """
  Whether a role can run an action of a task at all. A page asks this to
  decide what to show. The policy decides when the action runs.
  """
  @spec role_can?(atom | nil, atom) :: boolean
  def role_can?(role, action), do: Rescord.Accounts.granted?(role, Task, action)
end
