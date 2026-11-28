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

  alias Rescord.{Comments, Notifications, Transfers}
  alias RescordWeb.{CommentWords, Markdown, ResidentWords}

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

  # The hook `Push` sends the subscription of the browser.
  def handle_event(
        "push-subscribe",
        %{"endpoint" => endpoint, "keys" => %{} = keys} = params,
        socket
      )
      when is_binary(endpoint) do
    fields = %{
      endpoint: endpoint,
      device_key: text(keys["p256dh"]),
      auth: text(keys["auth"]),
      device: device(params["device"])
    }

    case Notifications.subscribe_device(fields, actor: socket.assigns.current_user) do
      {:ok, _device} ->
        {:reply, %{ok: true}, socket |> assign(problems: []) |> read()}

      {:error, error} ->
        problems = for {_field, words} <- Notifications.problems(error), do: words
        {:reply, %{ok: false}, assign(socket, problems: problems)}
    end
  end

  # The browser ended its subscription: the device goes from the list.
  def handle_event("push-unsubscribe", %{"endpoint" => endpoint}, socket)
      when is_binary(endpoint) do
    case Enum.find(socket.assigns.devices, &(&1.endpoint == endpoint)) do
      nil -> {:reply, %{ok: true}, socket}
      device -> remove(socket, device, reply?: true)
    end
  end

  def handle_event("remove-device", %{"device" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.devices, &(&1.id == id)) do
      nil -> {:noreply, socket}
      device -> remove(socket, device, reply?: false)
    end
  end

  def handle_event("ntfy-start", _params, socket),
    do: ntfy(socket, Notifications.start_ntfy(actor: socket.assigns.current_user))

  def handle_event("ntfy-renew", _params, %{assigns: %{ntfy: %{} = topic}} = socket),
    do: ntfy(socket, Notifications.renew_ntfy(topic, actor: socket.assigns.current_user))

  def handle_event("ntfy-stop", _params, %{assigns: %{ntfy: %{} = topic}} = socket),
    do: ntfy(socket, Notifications.stop_ntfy(topic, actor: socket.assigns.current_user))

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

  defp remove(socket, device, reply?: reply?) do
    result = Notifications.remove_device(device, actor: socket.assigns.current_user)
    socket = read(socket)

    case {result, reply?} do
      {:ok, true} -> {:reply, %{ok: true}, socket}
      {:ok, false} -> {:noreply, socket}
      {{:error, _error}, true} -> {:reply, %{ok: false}, socket}
      {{:error, _error}, false} -> {:noreply, put_flash(socket, :error, "That did not work.")}
    end
  end

  defp ntfy(socket, result) do
    case result do
      {:ok, _topic} -> {:noreply, socket |> assign(problems: []) |> read()}
      :ok -> {:noreply, socket |> assign(problems: []) |> read()}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "That did not work.")}
    end
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil

  # The kind of a device, which the hook guessed from the browser. It names
  # one of a short list, and makes no atom.
  @devices ~w(iphone ipad android mac windows linux)
  defp device(name) when name in @devices, do: String.to_existing_atom(name)
  defp device(_name), do: :other

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
      section={:notifications}
    >
      <.header>
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
          You have no notification. When a member tells you about a comment, or writes on a record that you follow, it is here.
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
          <small>A notification goes 30 days after you read it, and after 90 days in any case.</small>
        </p>
      </section>

      <section :if={@offer.web_push} aria-labelledby="device-heading">
        <h2 id="device-heading">This device</h2>
        <article
          id="push-device"
          data-device
          phx-hook="Push"
          phx-mounted={JS.ignore_attributes(["data-push"])}
          data-key={@offer.web_push}
        >
          <div data-when="ask">
            <p>
              This browser can show the notifications of Rescord when the page is closed. A notification says only that there is something new, and for which refuge: no name and no words of a comment.
            </p>
            <p>
              <button type="button" data-push-action="on">Get notifications on this device</button>
            </p>
          </div>
          <div data-when="on">
            <p>This device gets your notifications.</p>
            <p>
              <button type="button" data-variant="secondary" data-push-action="off">
                Stop notifications on this device
              </button>
            </p>
          </div>
          <div data-when="home-screen">
            <p>
              An iPhone or an iPad shows notifications of a site that is on its Home Screen. To add Rescord:
            </p>
            <ol>
              <li>Press Share in Safari.</li>
              <li>Press Add to Home Screen, then Add.</li>
              <li>Open Rescord from the Home Screen, sign in, and come back to this page.</li>
            </ol>
            <p><small>This needs iOS or iPadOS 16.4 or later.</small></p>
          </div>
          <div data-when="denied">
            <p>
              This browser blocks the notifications of Rescord. Allow them in the settings of the browser for this site, then come back to this page.
            </p>
          </div>
          <div data-when="none">
            <p>This browser cannot show notifications of a site.</p>
          </div>
          <noscript>
            <p>Notifications on a device need JavaScript.</p>
          </noscript>
        </article>
      </section>

      <section :if={@offer.web_push || @devices != []} aria-labelledby="devices-heading">
        <h2 id="devices-heading">Your devices</h2>
        <p :if={@devices == []}>No device gets your notifications.</p>
        <ul :if={@devices != []} data-devices>
          <li :for={device <- @devices} id={"device-#{device.id}"}>
            <span>
              {CommentWords.device(device.device)}
              <small>
                Since {since(@organisation, device.inserted_at)}
                <span :if={device.last_sent_at}>
                  · last sent {CommentWords.instant(@organisation, device.last_sent_at)}
                </span>
              </small>
            </span>
            <button
              type="button"
              data-variant="secondary"
              phx-click="remove-device"
              phx-value-device={device.id}
              aria-label={"Remove #{CommentWords.device(device.device)}, since #{since(@organisation, device.inserted_at)}"}
            >
              Remove
            </button>
          </li>
        </ul>
        <p><small>A device gets the notifications of each refuge that you are a member of.</small></p>
      </section>

      <section :if={@offer.ntfy} aria-labelledby="ntfy-heading">
        <h2 id="ntfy-heading">ntfy</h2>
        <div :if={is_nil(@ntfy)}>
          <p>
            Rescord can send your notifications to a topic of ntfy, which the ntfy app on a phone or a computer shows. A notification says only that there is something new, and for which refuge.
          </p>
          <p><button type="button" phx-click="ntfy-start">Get notifications on ntfy</button></p>
        </div>
        <div :if={@ntfy}>
          <p>Subscribe to this address in the ntfy app:</p>
          <p><output id="ntfy-address" data-address>{@ntfy_address}</output></p>
          <p>
            <small>
              Anyone who has the address can read what Rescord sends there. Keep it to yourself; a new address stops the old one.
            </small>
          </p>
          <p>
            <button type="button" data-variant="secondary" phx-click="ntfy-renew">New address</button>
            <button type="button" data-variant="secondary" phx-click="ntfy-stop">Stop notifications on ntfy</button>
          </p>
        </div>
      </section>

      <section :if={@channels != []} aria-labelledby="where-heading">
        <h2 id="where-heading">What goes where</h2>
        <form id="preferences-form" phx-submit="save-preferences">
          <fieldset :for={kind <- Rescord.Notifications.Notification.kinds()}>
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
          <button type="submit">Save</button>
        </form>
      </section>
    </Layouts.app>
    """
  end
end
