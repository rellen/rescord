defmodule RescordWeb.TaskLive do
  @moduledoc """
  One task, at `/o/<short name>/tasks/<id>` (issue 29): what it is, when it
  is due, whom it is for, who does it and its state, and its comments.

  The page of the tasks links each title here. A member takes a task, and
  completes it, on the page of its day, which the page links to. The page
  reads again when a task changes (ADR 0096).

  A task that the person cannot read, and one that is not there, give the
  same answer: the page of the tasks.
  """

  use RescordWeb, :live_view

  import RescordWeb.TaskComponents, only: [due: 3, for_words: 1, who: 3]

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.{ResidentWords, TaskWords}
  alias RescordWeb.Widgets.Comments

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case read(socket, id) do
      {:ok, task} ->
        {:ok, members} = Accounts.members([load: [:email]] ++ options(socket))

        {:ok,
         socket
         |> LiveChanges.listen([Tasks], &read_again/1)
         |> assign(
           members: members |> Enum.map(&{to_string(&1.email), &1.user_id}) |> Enum.sort()
         )
         |> put_task(task)
         |> Comments.assign_widget(:comments, {:task, task.id})}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such task.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/tasks")}
    end
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  defp read(socket, id) do
    with true <- is_binary(id),
         {:ok, _uuid} <- Ecto.UUID.cast(id),
         {:ok, %{} = task} <- Tasks.task_with_facts(id, options(socket)) do
      {:ok, task}
    else
      _no_task -> :error
    end
  end

  defp put_task(socket, task) do
    assign(socket,
      task: task,
      page_title: task.title,
      day: Accounts.local_date(socket.assigns.organisation, task.due_at),
      now: DateTime.utc_now()
    )
  end

  # Another person changed a task (ADR 0096). A task that went is gone from
  # the page too.
  defp read_again(socket) do
    case read(socket, socket.assigns.task.id) do
      {:ok, task} ->
        put_task(socket, task)

      :error ->
        socket
        |> put_flash(:info, "That task is no longer there.")
        |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/tasks")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:tasks}
    >
      <.header icon={Icons.section(:tasks)}>
        <:crumb navigate={~p"/o/#{@organisation.short_name}/tasks?#{[day: Date.to_iso8601(@day)]}"}>
          Tasks of {ResidentWords.date(@day)}
        </:crumb>
        {@task.title}
        <:subtitle>
          <.state kind={TaskWords.phase_kind(Tasks.phase(@task, @now))}>
            {TaskWords.phase(Tasks.phase(@task, @now))}
          </.state>
        </:subtitle>
      </.header>

      <dl>
        <dt>Due</dt>
        <dd>{due(@task, @organisation, true)}</dd>
        <dt>For</dt>
        <dd>{for_words(@task)}</dd>
        <dt>Who</dt>
        <dd>{who(@task, @members, @current_user)}</dd>
        <dt :if={@task.kind}>Kind</dt>
        <dd :if={@task.kind}>{@task.kind.label}</dd>
        <dt :if={@task.routine_id}>Routine</dt>
        <dd :if={@task.routine_id}>From a routine</dd>
        <dt :if={@task.note}>Note</dt>
        <dd :if={@task.note}>{@task.note}</dd>
        <dt :if={@task.skip_reason}>Why it was skipped</dt>
        <dd :if={@task.skip_reason}>{@task.skip_reason}</dd>
      </dl>
      <p>
        Take the task, or mark it as done, on the <.link navigate={
          ~p"/o/#{@organisation.short_name}/tasks?#{[day: Date.to_iso8601(@day)]}"
        }>tasks of its day</.link>.
      </p>

      <Comments.render state={@comments} record="this task" />
    </Layouts.app>
    """
  end
end
