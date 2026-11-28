defmodule RescordWeb.RootHealthLive do
  @moduledoc """
  The sanity checks of the server, for a root user, at `/root/health`
  (ADR 0114, issue 38): what each check found at its last run, for the
  server and for each organisation, since when, and what a fault means.
  "Run each check now" runs them all in a task of the page.

  A result holds a count and ids, never a value of a row. The ids are
  there for a root user to find the rows, not links into an organisation.

  "Alerts" is where a root user asks for an alert when a check fails
  (`Rescord.Health.Alerts`), and sets up where it goes: a device of Web
  Push, a topic of ntfy (`RescordWeb.DeviceComponents`). A device and a
  topic are of the person, so they also get the notifications of each
  organisation that the person is a member of.
  """

  use RescordWeb, :live_view

  import RescordWeb.DeviceComponents
  import RescordWeb.HealthComponents

  alias Rescord.{Health, Notifications}
  alias RescordWeb.{DeviceEvents, HealthWords}

  @device_events DeviceEvents.events()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Sanity checks", running?: false, problems: [])
     |> load()}
  end

  defp load(socket) do
    actor = socket.assigns.current_user
    opts = [actor: actor]
    results = Health.results(opts)

    groups =
      results
      |> Enum.chunk_by(& &1.organisation_id)
      |> Enum.map(fn [first | _rest] = rows -> {first.organisation, rows} end)

    assign(socket,
      groups: groups,
      summary: Health.summary(opts),
      checks: Health.checks(),
      watching?: Health.watching?(opts),
      offer: Notifications.offer(),
      devices: Notifications.devices(opts),
      ntfy: Notifications.ntfy_topic(opts),
      ntfy_address: Notifications.ntfy_address(opts)
    )
  end

  @impl true
  def handle_event("run", _params, socket) do
    if socket.assigns.running? do
      {:noreply, socket}
    else
      actor = socket.assigns.current_user

      {:noreply,
       socket
       |> assign(running?: true)
       |> start_async(:run, fn -> Health.run_now(actor: actor) end)}
    end
  end

  def handle_event("watch", params, socket) do
    watch? = get_in(params, ["alerts", "watch"]) == "true"

    case Health.watch(watch?, actor: socket.assigns.current_user) do
      :ok -> {:noreply, socket |> put_flash(:info, "Saved.") |> load()}
      {:error, _error} -> {:noreply, put_flash(socket, :error, "That did not work.")}
    end
  end

  def handle_event(event, params, socket) when event in @device_events,
    do: DeviceEvents.handle(event, params, socket, &load/1)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:run, {:ok, :ok}, socket) do
    {:noreply, socket |> assign(running?: false) |> put_flash(:info, "Each check ran.") |> load()}
  end

  def handle_async(:run, _other, socket) do
    {:noreply,
     socket
     |> assign(running?: false)
     |> put_flash(:error, "The checks did not finish. The log says why.")
     |> load()}
  end

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  defp day(%DateTime{} = instant), do: Calendar.strftime(instant, "%-d %B %Y")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <.header icon={Icons.section(:health)}>
        <:crumb navigate={~p"/root"}>Root</:crumb>
        Sanity checks
        <:subtitle>
          What the checks of the data and of the server found. They run on their own, and change nothing.
        </:subtitle>
      </.header>

      <.problems list={@problems} />

      <.overview summary={@summary} running?={@running?} />
      <.results :for={{organisation, rows} <- @groups} organisation={organisation} rows={rows} />

      <section aria-labelledby="alerts-heading">
        <h2 id="alerts-heading">Alerts</h2>
        <p>
          An alert says only that a check found a fault, with a link to this page: no check, no organisation and no count. It comes when a check starts to fail, and again each day that it still fails.
        </p>
        <p :if={!@offer.web_push && !@offer.ntfy}>
          The server sends no notifications yet. Turn on Web Push or ntfy on the page
          <.link navigate={~p"/root/push"}>Notifications on devices</.link>
          first.
        </p>
        <form id="alerts-form" phx-submit="watch">
          <input type="hidden" name="alerts[watch]" value="false" />
          <label>
            <input type="checkbox" name="alerts[watch]" value="true" checked={@watching?} />
            Send me an alert when a check fails
          </label>
          <button type="submit">Save</button>
        </form>
      </section>

      <.this_device :if={@offer.web_push} key={@offer.web_push} />

      <.device_list
        :if={@offer.web_push || @devices != []}
        devices={@devices}
        day={&day/1}
        time={&HealthWords.time/1}
      >
        A device gets the alerts of the checks that you ask for here, and the notifications of each organisation that you are a member of.
      </.device_list>

      <.ntfy_topic :if={@offer.ntfy} topic={@ntfy} address={@ntfy_address} />

      <.checks checks={@checks} />
    </Layouts.app>
    """
  end
end
