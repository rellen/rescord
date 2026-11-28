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
    extensions: [AshBoundary, AshPaperTrail.Domain, AshAi]

  require Ash.Query
  require Logger

  alias Rescord.Tasks.Changes.SyncTasks
  alias Rescord.Tasks.{Routine, Task, TaskSubject}

  boundary do
    # A relationship and a signal listener are checked too (ADR 0066).
    check aliases: true

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

  # The tools of the assistant (ADR 0069). A tool here does not exist for
  # Ruby until `Rescord.Ruby.Catalogue` names it, and it runs as the
  # member, with the policy of the action.
  tools do
    tool :get_task, Rescord.Tasks.Task, :read do
      description "Reads one task by its id, with its kind and what it is about."
      get_by :id
      load kind: [:label], subjects: [resident: [:name], location: []]
      # No id of a member goes to the provider: not who has the task, and
      # not who finished it.
      select [:id, :title, :note, :due_at, :state, :prescription_id, :skip_reason, :finished_at]
      annotations(read_only_hint: true)
    end
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

  @doc """
  The query that reads the tasks of one day for a page (ADR 0097): each
  task that is due on that day of the organisation, with its kind and its
  subjects, in the order of their times. With `earlier: true` it also has
  each task of an earlier day that is still due, which comes first, as the
  page of today shows. A collection of a page reads with it, and adds its
  filters, its search and its page.

  `opts` names the organisation in `:tenant`, and the actor.
  """
  @spec query_to_day(Date.t(), keyword) :: Ash.Query.t()
  def query_to_day(%Date{} = date, opts \\ []) do
    {earlier?, opts} = Keyword.pop(opts, :earlier, false)
    {from, to} = Rescord.Accounts.day_range(opts[:tenant], date)

    Task
    |> Ash.Query.for_read(:read, %{}, opts)
    |> on_day(from, to, earlier?)
    |> Ash.Query.sort(due_at: :asc, title: :asc, id: :asc)
    |> Ash.Query.load(@facts)
  end

  defp on_day(query, from, to, false),
    do: Ash.Query.filter(query, due_at >= ^from and due_at < ^to)

  defp on_day(query, from, to, true) do
    Ash.Query.filter(
      query,
      (due_at >= ^from and due_at < ^to) or (state == :due and due_at < ^from)
    )
  end

  @doc """
  One task of the query of a day (`query_to_day/2`, with the same `opts`),
  with its kind and its subjects, or `nil`: when there is no such task,
  when the day does not show it, and when the actor cannot read it. A page
  that gets the id of a task from the browser finds the task with this, so
  a text that is no id gives `nil` too.
  """
  @spec task_of_day(Date.t(), String.t(), keyword) ::
          {:ok, Ash.Resource.record() | nil} | {:error, term}
  def task_of_day(%Date{} = date, task_id, opts \\ []) when is_binary(task_id) do
    case Ecto.UUID.cast(task_id) do
      {:ok, task_id} ->
        date
        |> query_to_day(opts)
        |> Ash.Query.filter(id == ^task_id)
        |> Ash.read_one(Keyword.delete(opts, :earlier))

      :error ->
        {:ok, nil}
    end
  end

  @doc """
  Narrows a query of tasks to those of one person: `:anybody` gives the
  tasks that name no member, which are for each member, and the id of a
  user gives the tasks that name that user. It is the filter "Who" of the
  page of the tasks.
  """
  @spec for_person(Ash.Query.t(), :anybody | String.t()) :: Ash.Query.t()
  def for_person(%Ash.Query{} = query, :anybody),
    do: Ash.Query.filter(query, fragment("cardinality(?) = 0", assignee_ids))

  def for_person(%Ash.Query{} = query, user_id) when is_binary(user_id),
    do: Ash.Query.filter(query, ^user_id in assignee_ids)

  @doc "The tasks that are due and whose time is before `now`, the oldest first."
  def overdue(%DateTime{} = now, opts \\ []) do
    Task
    |> Ash.Query.filter(state == :due and due_at < ^now)
    |> Ash.Query.sort(due_at: :asc)
    |> Ash.Query.load(@facts)
    |> Ash.read(opts)
  end

  @doc """
  The tasks that need somebody now (ADR 0065): each task that is due and
  whose time is before the end of today in the organisation, the oldest
  first. A task of an earlier day that is still due is one of them.

  Returns `%{rows: rows, total: total}`. A row is
  `%{kind: :task, record: task, phase: phase}`, with the phase `:overdue` or
  `:due` at the instant `:now` of `opts`. There are at most `:limit` rows,
  and `total` counts each such task. A role that cannot complete a task
  gets no row: it can do nothing about one.
  """
  @spec attention(term, keyword) :: {:ok, %{rows: [map], total: non_neg_integer}} | {:error, term}
  def attention(role, opts \\ []) do
    {now, opts} = Keyword.pop(opts, :now, DateTime.utc_now())
    {limit, opts} = Keyword.pop(opts, :limit, 8)

    if role_can?(role, :complete) do
      today = Rescord.Accounts.local_date(opts[:tenant], now)
      {_start, finish} = Rescord.Accounts.day_range(opts[:tenant], today)
      query = Ash.Query.filter(Task, state == :due and due_at < ^finish)

      with {:ok, total} <- Ash.count(query, opts),
           {:ok, tasks} <-
             query
             |> Ash.Query.sort(due_at: :asc, title: :asc, id: :asc)
             |> Ash.Query.limit(limit)
             |> Ash.Query.load(@facts)
             |> Ash.read(opts) do
        rows = for task <- tasks, do: %{kind: :task, record: task, phase: phase(task, now)}
        {:ok, %{rows: rows, total: total}}
      end
    else
      {:ok, %{rows: [], total: 0}}
    end
  end

  @doc """
  The tasks of a calendar (ADR 0074): each task whose time is at `:from` of
  `opts` or after it, in the order of their times, `:limit` of them at
  most, each with its kind and its subjects.

  `scope` says which tasks: `:all`, `{:mine, user_id}` for the tasks that
  name a user, or `{:mine_and_open, user_id}` for those and the tasks that
  are for each member. Returns an entry for each task:
  `%{kind: :task, record: task, at: due_at}`.
  """
  @spec calendar(:all | {:mine | :mine_and_open, String.t()}, keyword) ::
          {:ok, [map]} | {:error, term}
  def calendar(scope, opts) do
    {from, opts} = Keyword.pop!(opts, :from)
    {limit, opts} = Keyword.pop(opts, :limit, 2_000)

    with {:ok, tasks} <-
           Task
           |> Ash.Query.filter(due_at >= ^from)
           |> named(scope)
           |> Ash.Query.sort(due_at: :asc, title: :asc, id: :asc)
           |> Ash.Query.limit(limit)
           |> Ash.Query.load(@facts)
           |> Ash.read(opts) do
      {:ok, for(task <- tasks, do: %{kind: :task, record: task, at: task.due_at})}
    end
  end

  defp named(query, :all), do: query
  defp named(query, {:mine, user_id}), do: for_person(query, user_id)

  # A task with no member is for each member.
  defp named(query, {:mine_and_open, user_id}) do
    Ash.Query.filter(
      query,
      ^user_id in assignee_ids or fragment("cardinality(?) = 0", assignee_ids)
    )
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
          Logger.error("The routine #{routine.id} got no tasks: #{Rescord.Log.reason(error)}")
          false
      end
    end)
  end

  # A routine whose tasks exist up to its horizon, or up to the end of its
  # last day, needs no write. A routine that ended thus costs nothing.
  defp up_to_date?(%{generated_until: nil}, _organisation, _now), do: false

  defp up_to_date?(routine, organisation, now) do
    horizon = SyncTasks.horizon(routine, organisation, now)

    limit =
      case routine.ends_on do
        nil ->
          horizon

        ends_on ->
          {_start, finish} = Rescord.Accounts.day_range(organisation, ends_on)
          Enum.min([horizon, finish], DateTime)
      end

    DateTime.compare(routine.generated_until, limit) != :lt
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
