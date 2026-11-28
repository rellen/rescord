defmodule RescordWeb.TaskComponents do
  @moduledoc """
  The parts of the page of the tasks (ADR 0032 and ADR 0037): the
  collection of the tasks of a day with what a member can do with each
  (ADR 0097), and the form of a new task.
  """

  use RescordWeb, :html

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.TaskWords

  @doc "The form of a new task, in a part of the page that is closed at first."
  attr :refused_form?, :any, required: true
  attr :problems, :any, required: true
  attr :form, :any, required: true
  attr :kinds, :any, required: true
  attr :residents, :any, required: true
  attr :groups, :any, required: true
  attr :locations, :any, required: true
  attr :members, :any, required: true

  def new_task(assigns) do
    ~H"""
    <details id="new-task">
      <summary><.icon name="plus" /> New task</summary>
      <.problems :if={@refused_form?} list={@problems} />
      <.form for={@form} id="task" phx-submit="plan">
        <.input field={@form[:title]} type="text" label="What to do" maxlength="120" required />
        <.input
          field={@form[:kind_id]}
          type="select"
          label="Kind"
          prompt="Not recorded"
          options={@kinds}
        />
        <.input field={@form[:date]} type="date" label="Day" required />
        <.input field={@form[:time]} type="time" label="Time" required />
        <.input
          field={@form[:resident_id]}
          type="select"
          label="For a resident"
          prompt="No resident"
          options={@residents}
        />
        <.input
          field={@form[:group_id]}
          type="select"
          label="For a group"
          prompt="No group"
          options={@groups}
        />
        <.input
          field={@form[:location_id]}
          type="select"
          label="For a location"
          prompt="No location"
          options={@locations}
        />
        <.members_field form={@form} name="task" members={@members} />
        <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
        <footer><.button type="submit">Plan the task</.button></footer>
      </.form>
    </details>
    """
  end

  attr :day, Date, required: true
  attr :today, Date, required: true
  attr :query, :any, required: true, doc: "the query of `Rescord.Tasks.query_to_day/2`"
  attr :url_state, :any, required: true
  attr :organisation, :map, required: true
  attr :members, :list, required: true
  attr :kinds, :list, required: true, doc: "each kind of task, as the choices of the filter"

  attr :people, :map,
    default: %{},
    doc: "the labels of `Rescord.Accounts.labels/1`, for a member who left"

  attr :for_person, :any, required: true, doc: "the function of the filter \"Who\""
  attr :user, :map, required: true
  attr :role, :atom, required: true
  attr :now, :any, required: true

  @doc """
  The tasks of a day, as a collection of Cinder (ADR 0097): a search on the
  title, filters on the state, the kind and the person, and pages. Each row
  has what a member can do with the task. On the page of today, the tasks
  of earlier days that are still due come first, each with its day.
  """
  def tasks(assigns) do
    ~H"""
    <section id="day-tasks" aria-labelledby="day-heading">
      <h2 id="day-heading">Tasks of the day</h2>
      <p :if={@day == @today}>
        The overdue tasks of earlier days come first, each with its day.
      </p>
      <Cinder.collection
        id="tasks"
        query={@query}
        actor={@user}
        tenant={@organisation}
        url_state={@url_state}
        page_size={[default: 50, options: [50, 100, 200]]}
        search={[label: "Search", placeholder: "A word of the title"]}
      >
        <:filter
          field="who"
          type="select"
          label="Who"
          prompt="All tasks"
          options={who_options(@members)}
          fn={@for_person}
        />
        <:filter field="kind_id" type="select" label="Kind" prompt="Any kind" options={@kinds} />
        <:empty :let={found}>
          <p :if={found.filtered?}>No task matches the search and the filters.</p>
          <p :if={not found.filtered?}>
            There is no task on this day. Plan one with New task, or make tasks that repeat with a routine.
          </p>
        </:empty>
        <:col :let={task} field="title" label="Task" search>
          <%!-- The place of a link from the first page or a calendar:
               `tasks#task-<id>`. Cinder writes the row, with no id. --%>
          <.link id={"task-#{task.id}"} navigate={~p"/o/#{@organisation.short_name}/tasks/#{task.id}"}>
            {task.title}
          </.link>
          <small :if={task.kind}>{task.kind.label}</small>
          <small :if={task.routine_id}>From a routine</small>
          <small :if={task.note}>{task.note}</small>
          <small :if={task.skip_reason}>Skipped: {task.skip_reason}</small>
        </:col>
        <:col :let={task} field="due_at" label="Due">
          <span data-label="Due">{due(task, @organisation, earlier?(task, @organisation, @day))}</span>
        </:col>
        <:col :let={task} label="For">
          <span data-label="For">{for_words(task)}</span>
        </:col>
        <:col :let={task} field="assignee_ids" label="Who">
          <span data-label="Who">{who(task, @members, @user, @people)}</span>
        </:col>
        <:col
          :let={task}
          field="state"
          label="State"
          filter={[type: :select, prompt: "Any state", options: TaskWords.state_options()]}
        >
          <.state kind={TaskWords.phase_kind(Tasks.phase(task, @now))}>
            {TaskWords.phase(Tasks.phase(task, @now))}
          </.state>
        </:col>
        <:col :let={task} label="Actions">
          <.actions task={task} user={@user} role={@role} />
        </:col>
      </Cinder.collection>
    </section>
    """
  end

  attr :task, :map, required: true
  attr :user, :map, required: true
  attr :role, :atom, required: true

  # What a member can do with a task.
  defp actions(assigns) do
    ~H"""
    <.button
      :if={
        @task.state == :due and @user.id not in @task.assignee_ids and
          Tasks.role_can?(@role, :take)
      }
      phx-click="take"
      phx-value-id={@task.id}
      aria-label={"Take the task #{@task.title}"}
    >
      <.icon name="user" /> Take
    </.button>
    <.button
      :if={@task.state == :due and Tasks.role_can?(@role, :complete)}
      phx-click="complete"
      phx-value-id={@task.id}
      aria-label={"Mark the task #{@task.title} as done"}
    >
      <.icon name="check" /> Done
    </.button>
    <.button
      :if={@task.state != :due and Tasks.role_can?(@role, :reopen)}
      phx-click="reopen"
      phx-value-id={@task.id}
      aria-label={"Open again the task #{@task.title}"}
    >
      <.icon name="arrow-uturn-left" /> Open again
    </.button>
    <details
      :if={@task.state == :due and Tasks.role_can?(@role, :skip)}
      id={"skip-details-#{@task.id}"}
    >
      <summary aria-label={"Skip the task #{@task.title}"}><.icon name="forward" /> Skip</summary>
      <form id={"skip-#{@task.id}"} phx-submit="skip">
        <input type="hidden" name="task_id" value={@task.id} />
        <.input
          id={"skip-#{@task.id}-reason"}
          name="skip[reason]"
          type="text"
          label={"Why you skip #{@task.title}"}
          value=""
          maxlength="200"
          required
        />
        <.button type="submit">Skip the task</.button>
      </form>
    </details>
    """
  end

  # The choices of the filter "Who": the person who reads, the tasks that
  # name no member, and each member.
  defp who_options(members), do: [{"Given to me", "me"}, {"Open to anybody", "anybody"} | members]

  # Whether a task is of a day before the day of the page: it then shows
  # its day with its time.
  defp earlier?(task, organisation, day),
    do: Date.before?(Accounts.local_date(organisation, task.due_at), day)

  def due(task, organisation, with_day?) do
    local = Accounts.local_time(organisation, task.due_at)

    if with_day?,
      do: "#{RescordWeb.ResidentWords.date(DateTime.to_date(local))}, #{TaskWords.time(local)}",
      else: TaskWords.time(local)
  end

  def for_words(task) do
    case Tasks.subject_names(task) do
      [] -> "Nothing in particular"
      names -> Enum.join(names, ", ")
    end
  end

  def who(task, members, user, people \\ %{})
  def who(%{assignee_ids: []}, _members, _user, _people), do: "Anybody"

  # A root user is not a member, and reads a task that they took as their own.
  # A former member is in `people` (ADR 0105).
  def who(%{assignee_ids: ids}, members, user, people) do
    ids
    |> Enum.map(fn id ->
      Enum.find_value(members, fn {email, user_id} -> if user_id == id, do: email end) ||
        cond do
          id == user.id -> to_string(user.email)
          Map.has_key?(people, id) -> people[id]
          true -> "A person who is not a member now"
        end
    end)
    |> Enum.join(", ")
  end

  @doc """
  The members that a task or a routine is for, as a box for each member.
  With no box ticked, it is for anybody. When one of them completes a task,
  it is done.
  """
  attr :form, :any, required: true
  attr :name, :string, required: true, doc: "the name of the form in the fields"
  attr :members, :list, required: true

  def members_field(assigns) do
    assigns = assign(assigns, chosen: List.wrap(assigns.form[:assignee_ids].value))

    ~H"""
    <fieldset id={"#{@name}-members"} aria-describedby={"#{@name}-members-hint"}>
      <legend>Who does it</legend>
      <small id={"#{@name}-members-hint"} data-hint>
        Tick one or more members, or none so that anybody can. The task is done when one of them does it.
      </small>
      <label :for={{email, id} <- @members}>
        <input type="checkbox" name={"#{@name}[assignee_ids][]"} value={id} checked={id in @chosen} />
        {email}
      </label>
    </fieldset>
    """
  end
end
