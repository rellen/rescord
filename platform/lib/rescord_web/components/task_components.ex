defmodule RescordWeb.TaskComponents do
  @moduledoc """
  The parts of the page of the tasks (ADR 0032 and ADR 0037): a table of
  tasks with what a member can do with each, and the form of a new task.
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
      <summary>New task</summary>
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
        <.input
          field={@form[:assignee_id]}
          type="select"
          label="Who does it"
          prompt="Anybody"
          options={@members}
        />
        <.input field={@form[:note]} type="text" label="Note" maxlength="1000" />
        <footer><.button type="submit">Plan the task</.button></footer>
      </.form>
    </details>
    """
  end

  attr :tasks, :list, required: true
  attr :organisation, :map, required: true
  attr :members, :list, required: true
  attr :user, :map, required: true
  attr :role, :atom, required: true
  attr :now, :any, required: true
  attr :with_day, :boolean, default: false, doc: "shows the day of each task with its time"

  # A table of tasks, each with its state and what a member can do with it.
  def tasks(assigns) do
    ~H"""
    <div data-scroll>
      <table>
        <thead>
          <tr>
            <th scope="col">Due</th>
            <th scope="col">Task</th>
            <th scope="col">For</th>
            <th scope="col">Who</th>
            <th scope="col">State</th>
            <th scope="col">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={task <- @tasks} id={"task-#{task.id}"}>
            <td>{due(task, @organisation, @with_day)}</td>
            <td>
              {task.title}
              <small :if={task.kind}>{task.kind.label}</small>
              <small :if={task.routine_id}>From a routine</small>
              <small :if={task.note}>{task.note}</small>
              <small :if={task.skip_reason}>Skipped: {task.skip_reason}</small>
            </td>
            <td>{for_words(task)}</td>
            <td>{who(task, @members, @user)}</td>
            <td>
              <.state kind={TaskWords.phase_kind(Tasks.phase(task, @now))}>
                {TaskWords.phase(Tasks.phase(task, @now))}
              </.state>
            </td>
            <td>
              <.button
                :if={
                  task.state == :due and task.assignee_id != @user.id and
                    Tasks.role_can?(@role, :take)
                }
                phx-click="take"
                phx-value-id={task.id}
                aria-label={"Take the task #{task.title}"}
              >
                Take
              </.button>
              <.button
                :if={task.state == :due and Tasks.role_can?(@role, :complete)}
                phx-click="complete"
                phx-value-id={task.id}
                aria-label={"Mark the task #{task.title} as done"}
              >
                Done
              </.button>
              <.button
                :if={task.state != :due and Tasks.role_can?(@role, :reopen)}
                phx-click="reopen"
                phx-value-id={task.id}
                aria-label={"Open the task #{task.title} again"}
              >
                Open again
              </.button>
              <details
                :if={task.state == :due and Tasks.role_can?(@role, :skip)}
                id={"skip-details-#{task.id}"}
              >
                <summary>Skip</summary>
                <form id={"skip-#{task.id}"} phx-submit="skip">
                  <input type="hidden" name="task_id" value={task.id} />
                  <.input
                    id={"skip-#{task.id}-reason"}
                    name="skip[reason]"
                    type="text"
                    label={"Why you skip #{task.title}"}
                    value=""
                    maxlength="200"
                    required
                  />
                  <.button type="submit">Skip the task</.button>
                </form>
              </details>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

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

  def who(%{assignee_id: nil}, _members, _user), do: "Anybody"

  # A root user is not a member, and reads a task that they took as their own.
  def who(%{assignee_id: id}, members, user) do
    Enum.find_value(members, fn {email, user_id} -> if user_id == id, do: email end) ||
      if(id == user.id, do: to_string(user.email), else: "A person who is not a member now")
  end
end
