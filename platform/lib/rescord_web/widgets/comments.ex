defmodule RescordWeb.Widgets.Comments do
  @moduledoc """
  The comments of one record, as a part of its page (issue 29, ADR 0106):
  the comments, the form to write one with "Tell someone", the buttons of
  the writer's own comment, and the line about following. The pages of a
  resident, a task, a transfer and an expense use it with two lines:

      socket |> Comments.assign_widget(:comments, {:resident, resident.id})

      <Comments.render state={@comments} />

  It is the first live widget (ADR 0037): a part with state of its own that
  four pages share. It reads as the person of the page, through
  `Rescord.Comments`, and listens for the changes of the comments of the
  organisation (ADR 0096). When it reads, it marks the notifications of
  the person about this record as read: they have it in front of them.

  The words of a comment are a small part of Markdown, which
  `RescordWeb.Markdown` writes as HTML.
  """

  use RescordWeb, :widget
  use ShoddyPhoenix.LiveView.Events, prefix: "comments"

  alias Rescord.{Changes, Comments, Notifications}
  alias RescordWeb.{CommentWords, Markdown}
  alias ShoddyPhoenix.LiveView

  import Shoddy.Strings, only: [non_blank: 1]

  defstruct [
    :key,
    :subject,
    :organisation,
    :user_id,
    comments: [],
    people: %{},
    others: [],
    following?: false,
    can_write?: false,
    can_delete: MapSet.new(),
    can_revise: MapSet.new(),
    problems: [],
    draft: "",
    told: [],
    form: 0
  ]

  @doc """
  Puts the widget of the comments of `subject` on the page under `key`,
  and reads them. The socket has the assigns of the live session of an
  organisation.
  """
  def assign_widget(socket, key, subject) do
    state = %__MODULE__{
      key: key,
      subject: subject,
      organisation: socket.assigns.organisation,
      user_id: socket.assigns.current_user.id
    }

    socket
    |> Widget.put(read(state, socket))
    |> LiveView.when_connected(&listen/1)
    |> LiveView.when_connected(&mark_read(&1, subject))
  end

  defp listen(socket) do
    if socket.private[{__MODULE__, :listening}] do
      socket
    else
      socket =
        for topic <- Changes.topics(socket.assigns.organisation, Comments), reduce: socket do
          socket -> Subscriptions.subscribe(socket, Changes.pubsub(), topic, __MODULE__)
        end

      socket
      |> Phoenix.LiveView.put_private({__MODULE__, :listening}, true)
      |> Widgets.route_events(event_prefix(), &handle_event/3)
      |> LiveView.put_hook({__MODULE__, :info}, :handle_info, &handle_info/2)
    end
  end

  # The person has the record in front of them.
  defp mark_read(socket, subject) do
    Notifications.mark_read_on(subject, options(socket))
    recount(socket)
  end

  # The page does not hear its own writes (ADR 0096), so the count of the
  # header is set here.
  defp recount(socket) do
    if Map.has_key?(socket.assigns, :inbox),
      do: Phoenix.Component.assign(socket, :inbox, Notifications.unread_count(options(socket))),
      else: socket
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  # What the widget shows, read as the person of the page.
  defp read(state, socket) do
    opts = options(socket)
    role = socket.assigns.role
    user = socket.assigns.current_user
    {:ok, comments} = Comments.comments_on(state.subject, opts)
    people = Comments.people(comments, opts)

    %{
      state
      | comments: comments,
        people: people,
        others:
          for(
            {user_id, {email, :member}} <- people,
            user_id != user.id,
            do: {user_id, email}
          )
          |> Enum.sort_by(&elem(&1, 1)),
        following?: Comments.following?(state.subject, opts),
        can_write?: Comments.role_can?(role, :write),
        can_revise: allowed(comments, role, user, :revise),
        can_delete: allowed(comments, role, user, :delete)
    }
  end

  defp allowed(comments, role, user, action) do
    for comment <- comments, Comments.can?(role, user, comment, action), into: MapSet.new() do
      comment.id
    end
  end

  defp again(socket, key, fun \\ & &1) do
    case Widget.fetch(socket, __MODULE__, key) do
      {:ok, state} -> socket |> Widget.put(state |> fun.() |> read(socket)) |> recount()
      :error -> socket
    end
  end

  ## Events

  defp handle_event("post", %{"widget" => key, "comment" => %{} = fields}, socket) do
    with {:ok, state} <- Widget.fetch(socket, __MODULE__, key) do
      body = non_blank(fields["body"])
      allowed = MapSet.new(state.others, &elem(&1, 0))
      told = for id <- List.wrap(fields["told"]), is_binary(id), id in allowed, uniq: true, do: id

      case Comments.write(state.subject, %{body: body, told_ids: told}, options(socket)) do
        {:ok, _comment} ->
          {:noreply,
           again(socket, key, &%{&1 | problems: [], draft: "", told: [], form: &1.form + 1})}

        {:error, error} ->
          problems = for {_field, words} <- Comments.problems(error), do: words

          {:noreply,
           Widget.put(socket, %{state | problems: problems, draft: body || "", told: told})}
      end
    else
      :error -> {:noreply, socket}
    end
  end

  defp handle_event(
         "revise",
         %{"widget" => key, "comment_id" => id, "comment" => %{"body" => body}},
         socket
       )
       when is_binary(id) and is_binary(body) do
    act(socket, key, id, &Comments.revise_comment(&1, non_blank(body), &2))
  end

  defp handle_event("delete", %{"widget" => key, "comment_id" => id}, socket) when is_binary(id),
    do: act(socket, key, id, &Comments.delete_comment/2)

  defp handle_event("follow", %{"widget" => key}, socket) do
    with {:ok, state} <- Widget.fetch(socket, __MODULE__, key) do
      Comments.follow(state.subject, options(socket))
      {:noreply, again(socket, key)}
    else
      :error -> {:noreply, socket}
    end
  end

  defp handle_event("unfollow", %{"widget" => key}, socket) do
    with {:ok, state} <- Widget.fetch(socket, __MODULE__, key) do
      Comments.unfollow(state.subject, options(socket))
      {:noreply, again(socket, key)}
    else
      :error -> {:noreply, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:noreply, socket}

  # An event names a comment by its id: the widget takes it only from the
  # comments that it read as the person (AGENTS.md, the journal page).
  defp act(socket, key, id, fun) do
    with {:ok, state} <- Widget.fetch(socket, __MODULE__, key),
         %Comments.Comment{} = comment <- Enum.find(state.comments, &(&1.id == id)) do
      case fun.(comment, options(socket)) do
        :ok ->
          {:noreply, again(socket, key, &%{&1 | problems: []})}

        {:ok, _comment} ->
          {:noreply, again(socket, key, &%{&1 | problems: []})}

        {:error, error} ->
          problems = for {_field, words} <- Comments.problems(error), do: words
          {:noreply, Widget.put(socket, %{state | problems: problems})}
      end
    else
      _none -> {:noreply, socket}
    end
  end

  defp handle_info(%Changes.Change{domain: Comments}, socket) do
    socket =
      Widget.update_each(socket, __MODULE__, &read(&1, socket))
      |> then(fn socket ->
        socket
        |> Widget.instances(__MODULE__)
        |> Enum.reduce(socket, &mark_read(&2, &1.subject))
      end)

    {:cont, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  ## The part of the page

  attr :state, __MODULE__, required: true
  attr :record, :string, required: true, doc: "the record in words, such as \"Hazel\""

  attr :partner?, :boolean,
    default: false,
    doc: "a transfer: say that the partner does not see the comments"

  def render(assigns) do
    ~H"""
    <section id={"comments-#{@state.key}"} aria-labelledby={"comments-#{@state.key}-heading"}>
      <h2 id={"comments-#{@state.key}-heading"}>Comments</h2>
      <p>
        <small>
          Each member who can open {@record} reads these comments. They are kept with the records of {@state.organisation.name}{if @partner?,
            do: ", and the partner refuge does not see them"}.
        </small>
      </p>

      <.problems list={@state.problems} />

      <p :if={@state.comments == []}>No comment yet.</p>
      <ol :if={@state.comments != []} data-comments>
        <li
          :for={comment <- @state.comments}
          :key={comment.id}
          id={"comment-#{comment.id}"}
          data-own={comment.author_id == @state.user_id}
        >
          <article>
            <header>
              <strong>{CommentWords.person(@state.people, comment.author_id)}</strong>
              <time datetime={DateTime.to_iso8601(comment.inserted_at)}>
                {CommentWords.instant(@state.organisation, comment.inserted_at)}
              </time>
              <small :if={comment.edited_at}>changed</small>
            </header>
            <Markdown.markdown text={comment.body} />
            <footer :if={
              comment.told_ids != [] or MapSet.member?(@state.can_revise, comment.id) or
                MapSet.member?(@state.can_delete, comment.id)
            }>
              <p :if={comment.told_ids != []}>
                Told {Enum.map_join(comment.told_ids, ", ", &CommentWords.person(@state.people, &1))}
              </p>
              <details
                :if={MapSet.member?(@state.can_revise, comment.id)}
                id={"change-comment-#{comment.id}"}
              >
                <summary>Change</summary>
                <form
                  id={"change-comment-#{comment.id}-form"}
                  phx-submit={event("revise")}
                >
                  <input type="hidden" name="widget" value={@state.key} />
                  <input type="hidden" name="comment_id" value={comment.id} />
                  <.input
                    id={"comment-#{comment.id}-body"}
                    name="comment[body]"
                    type="textarea"
                    label="The comment"
                    value={comment.body}
                    rows="3"
                    maxlength="4000"
                    required
                    hint={"A change tells nobody again. The comment then says \"changed\", and Rescord keeps no copy of the old words."}
                  />
                  <footer><button type="submit">Save the change</button></footer>
                </form>
              </details>
              <.confirm
                :if={MapSet.member?(@state.can_delete, comment.id)}
                id={"delete-comment-#{comment.id}"}
                summary="Delete"
              >
                <p>Its words go for good.</p>
                <.button
                  type="button"
                  variant="danger"
                  phx-click={event("delete")}
                  phx-value-widget={@state.key}
                  phx-value-comment_id={comment.id}
                >
                  Delete the comment
                </.button>
              </.confirm>
            </footer>
          </article>
        </li>
      </ol>

      <form
        :if={@state.can_write?}
        id={"comment-form-#{@state.key}-#{@state.form}"}
        phx-submit={event("post")}
        data-comment
      >
        <input type="hidden" name="widget" value={@state.key} />
        <.input
          id={"comment-body-#{@state.key}"}
          name="comment[body]"
          type="textarea"
          label="Write a comment"
          value={@state.draft}
          rows="3"
          maxlength="4000"
          required
          hint="Up to 4,000 characters. **Bold**, *italics*, a list with - or 1., and a link with [words](https://…). Each member who gets notifications for this gets one."
        />
        <details :if={@state.others != []} id={"comment-tell-#{@state.key}"}>
          <summary>Tell someone</summary>
          <fieldset>
            <legend>Members to tell</legend>
            <label :for={{user_id, email} <- @state.others}>
              <input
                type="checkbox"
                name="comment[told][]"
                value={user_id}
                checked={user_id in @state.told}
              />
              {email}
            </label>
            <small>
              A member who is told gets a notification, and gets notifications for this from then on. A member who cannot open this record gets none.
            </small>
          </fieldset>
        </details>
        <footer>
          <button type="submit">Post</button>
        </footer>
      </form>

      <p :if={@state.following?} data-follow>
        You get a notification for each new comment here.
        <button
          type="button"
          data-variant="secondary"
          phx-click={event("unfollow")}
          phx-value-widget={@state.key}
        >
          Stop notifications for this
        </button>
      </p>
      <p :if={!@state.following? and @state.can_write?} data-follow>
        You get no notification for this.
        <button
          type="button"
          data-variant="secondary"
          phx-click={event("follow")}
          phx-value-widget={@state.key}
        >
          Get notifications for this
        </button>
      </p>
    </section>
    """
  end
end
