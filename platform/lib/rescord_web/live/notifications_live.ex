defmodule RescordWeb.NotificationsLive do
  @moduledoc """
  The notifications of the person, at `/o/<short name>/notifications`
  (issue 29, ADR 0106).

  The page lists the newest notifications of the person in this
  organisation, each with a link to its record and the words of its
  comment, and marks them all as read on a press. Opening the record marks
  its notifications as read too (`RescordWeb.Widgets.Comments`).

  It also holds how the notifications leave the app, where the server has
  the channel:

    * "This device": the hook `Push` (`assets/js/push.ts`) asks the browser
      for a subscription of Web Push and sends it here. A browser that
      cannot, and an iPhone that has not put Rescord on its Home Screen,
      get words instead of the button.
    * "Your devices": each device of the person, with a button to take it
      off.
    * "ntfy": a topic of the person's own, with its address, a new address,
      and a stop.
    * "What goes where": the channels of each kind of notification.

  A device and a topic are of the person, not of the organisation: they
  get the notifications of each organisation of the person. The page acts
  only on a device that it read as the person.
  """

  use RescordWeb, :live_view

  import RescordWeb.DeviceComponents

  alias Rescord.{Comments, Notifications, Transfers}
  alias RescordWeb.{CommentWords, DeviceEvents, Markdown, ResidentWords}

  @device_events DeviceEvents.events()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Notifications", problems: [], offer: Notifications.offer())
     |> LiveChanges.listen([Notifications], &read/1)
     |> read()}
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  defp read(socket) do
    opts = options(socket)
    {:ok, notifications} = Notifications.notifications_with_records(opts)

    assign(socket,
      notifications: Enum.map(notifications, &row(&1, socket)),
      people: Comments.people(Enum.map(notifications, & &1.comment), opts),
      inbox: Notifications.unread_count(opts),
      devices: Notifications.devices(opts),
      ntfy: Notifications.ntfy_topic(opts),
      ntfy_address: Notifications.ntfy_address(opts),
      preferences: Notifications.preferences(opts)
    )
  end

  # A notification with what the page shows of its record.
  defp row(notification, socket) do
    comment = notification.comment
    {kind, id} = Comments.Subject.of(comment)
    short = socket.assigns.organisation.short_name

    {name, path} =
      case kind do
        :resident ->
          {comment.resident && comment.resident.name, ~p"/o/#{short}/residents/#{id}"}

        :task ->
          {comment.task && comment.task.title, ~p"/o/#{short}/tasks/#{id}"}

        :expense ->
          {comment.expense && comment.expense.description, ~p"/o/#{short}/expenses/#{id}"}

        :transfer ->
          {transfer_name(socket, id), ~p"/o/#{short}/transfers/#{id}"}

        :journal_entry ->
          entry_row(comment.journal_entry, short, id)
      end

    %{
      notification: notification,
      comment: comment,
      kind: kind,
      name: name || CommentWords.record(kind),
      href: path <> "#comment-#{comment.id}"
    }
  end

  # An entry names its resident; the page of the journal shows the one entry.
  defp entry_row(%{resident_id: resident_id} = entry, short, id) do
    name = entry.resident && "An entry about #{entry.resident.name}"
    {name, ~p"/o/#{short}/residents/#{resident_id}/journal?entry=#{id}"}
  end

  defp entry_row(_none, short, _id), do: {nil, ~p"/o/#{short}/notifications"}

  defp transfer_name(socket, id) do
    case Transfers.transfer_of(socket.assigns.organisation, id,
           actor: socket.assigns.current_user
         ) do
      {:ok, %{resident_name: name}} when is_binary(name) -> "Transfer of #{name}"
      _other -> nil
    end
  end

  ## Events

  @impl true
  def handle_event("mark-all-read", _params, socket) do
    :ok = Notifications.mark_all_read(options(socket))
    {:noreply, read(socket)}
  end

  # The devices and the topic of ntfy (`RescordWeb.DeviceComponents`).
  def handle_event(event, params, socket) when event in @device_events,
    do: DeviceEvents.handle(event, params, socket, &read/1)

  def handle_event("save-preferences", %{"preferences" => %{} = chosen}, socket) do
    offered = offered(socket.assigns.offer)

    results =
      for kind <- Rescord.Notifications.Notification.kinds() do
        picked = List.wrap(chosen[Atom.to_string(kind)])
        # A channel that the server does not offer keeps what it was.
        kept = Enum.reject(socket.assigns.preferences[kind], &(&1 in offered))
        channels = Enum.filter(offered, &(Atom.to_string(&1) in picked)) ++ kept
        Notifications.set_preference(kind, channels, options(socket))
      end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        {:noreply, socket |> assign(problems: []) |> put_flash(:info, "Saved.") |> read()}

      {:error, error} ->
        problems = for {_field, words} <- Notifications.problems(error), do: words
        {:noreply, assign(socket, problems: problems)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp offered(offer) do
    for {key, on} <- [web_push: offer.web_push, ntfy: offer.ntfy], on, do: key
  end

  defp since(organisation, instant),
    do: ResidentWords.date(Rescord.Accounts.local_date(organisation, instant))

  ## The page

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :channels, offered(assigns.offer))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:notifications}
    >
      <.header icon={Icons.section(:notifications)}>
        Notifications
        <:subtitle>
          {if @inbox == 0, do: "Nothing new", else: "#{@inbox} new"}, for {@organisation.name}
        </:subtitle>
        <:actions :if={@inbox > 0}>
          <button type="button" data-variant="secondary" phx-click="mark-all-read">
            Mark all as read
          </button>
        </:actions>
      </.header>

      <.problems list={@problems} />

      <section aria-labelledby="list-heading">
        <h2 id="list-heading">The newest</h2>
        <p :if={@notifications == []}>
          You have no notification yet. One comes here when a member tells you about a comment, or when somebody comments on a record where you pressed Get notifications for this.
        </p>
        <ul :if={@notifications != []} data-notifications>
          <li
            :for={row <- @notifications}
            id={"notification-#{row.notification.id}"}
            data-new={is_nil(row.notification.read_at)}
          >
            <p>
              <.link navigate={row.href}>{row.name}</.link>
              <.state :if={is_nil(row.notification.read_at)} kind="info">New</.state>
            </p>
            <blockquote><Markdown.markdown text={row.comment.body} /></blockquote>
            <small>
              {CommentWords.notification(
                row.notification.kind,
                CommentWords.person(@people, row.comment.author_id),
                row.kind
              )} ·
              <time datetime={DateTime.to_iso8601(row.comment.inserted_at)}>
                {CommentWords.instant(@organisation, row.comment.inserted_at)}
              </time>
            </small>
          </li>
        </ul>
        <p>
          <small>Rescord deletes a notification 30 days after you read it, or 90 days after it came.</small>
        </p>
      </section>

      <.this_device :if={@offer.web_push} key={@offer.web_push} />

      <.device_list
        :if={@offer.web_push || @devices != []}
        devices={@devices}
        day={&since(@organisation, &1)}
        time={&CommentWords.instant(@organisation, &1)}
      >
        A device gets the notifications of each organisation that you are a member of.
      </.device_list>

      <.ntfy_topic :if={@offer.ntfy} topic={@ntfy} address={@ntfy_address} />

      <section :if={@channels != []} aria-labelledby="where-heading">
        <h2 id="where-heading">What goes where</h2>
        <form id="preferences-form" phx-submit="save-preferences">
          <fieldset
            :for={kind <- Rescord.Notifications.Notification.kinds()}
            id={"preferences-#{kind}"}
          >
            <legend>{CommentWords.kind(kind)}</legend>
            <input type="hidden" name={"preferences[#{kind}][]"} value="" />
            <label :for={channel <- @channels}>
              <input
                type="checkbox"
                name={"preferences[#{kind}][]"}
                value={channel}
                checked={channel in @preferences[kind]}
              />
              {CommentWords.channel(channel)}
            </label>
          </fieldset>
          <p><small>Each notification is on this page in any case.</small></p>
          <footer><button type="submit">Save</button></footer>
        </form>
      </section>
    </Layouts.app>
    """
  end
end
