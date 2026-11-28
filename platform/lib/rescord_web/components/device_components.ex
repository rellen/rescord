defmodule RescordWeb.DeviceComponents do
  @moduledoc """
  The parts of a page with which a person sets up where their
  notifications go outside the app (issue 29, ADR 0106): "This device"
  (Web Push), "Your devices", and "ntfy". The page of the notifications of
  an organisation shows them, and so does `/root/health` for the alerts of
  the sanity checks (ADR 0114): a device and a topic are of the person, not
  of an organisation, so a root user who is a member of no organisation
  sets them up there.

  `RescordWeb.DeviceEvents` handles the events of these parts, for each
  page that shows them.
  """

  use RescordWeb, :html

  alias RescordWeb.CommentWords

  @doc """
  The device of the browser: the hook `Push` (`assets/js/push.ts`) asks
  the browser for a subscription of Web Push and sends it to the page.
  """
  attr :key, :string, required: true, doc: "the public key of Web Push of the server"

  def this_device(assigns) do
    ~H"""
    <section aria-labelledby="device-heading">
      <h2 id="device-heading">This device</h2>
      <article
        id="push-device"
        data-device
        phx-hook="Push"
        phx-mounted={JS.ignore_attributes(["data-push"])}
        data-key={@key}
      >
        <div data-when="ask">
          <p>
            This browser can show the notifications of Rescord when the page is closed. A notification says only that there is something new, and for which organisation: no name and no words of a comment.
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
    """
  end

  @doc "Each device of the person, with a button to take it off."
  attr :devices, :list, required: true
  attr :day, :any, required: true, doc: "a function that gives the words of the day of an instant"
  attr :time, :any, required: true, doc: "a function that gives the words of an instant"
  slot :inner_block, required: true, doc: "what the devices get"

  def device_list(assigns) do
    ~H"""
    <section aria-labelledby="devices-heading">
      <h2 id="devices-heading">Your devices</h2>
      <p :if={@devices == []}>No device gets your notifications.</p>
      <ul :if={@devices != []} data-devices>
        <li :for={device <- @devices} id={"device-#{device.id}"}>
          <span>
            {CommentWords.device(device.device)}
            <small>
              Since {@day.(device.inserted_at)}
              <span :if={device.last_sent_at}>
                · last sent {@time.(device.last_sent_at)}
              </span>
            </small>
          </span>
          <.confirm
            id={"remove-device-#{device.id}"}
            summary="Remove"
            label={"Remove #{CommentWords.device(device.device)}, since #{@day.(device.inserted_at)}"}
          >
            <p>The device gets no more notifications until you turn them on there again.</p>
            <.button
              type="button"
              variant="danger"
              phx-click="remove-device"
              phx-value-device={device.id}
            >
              Remove {CommentWords.device(device.device)}, since {@day.(device.inserted_at)}
            </.button>
          </.confirm>
        </li>
      </ul>
      <p><small>{render_slot(@inner_block)}</small></p>
    </section>
    """
  end

  @doc "The topic of ntfy of the person: its address, a new address, and a stop."
  attr :topic, :any, required: true, doc: "the topic of the person, or nil"
  attr :address, :string, default: nil

  def ntfy_topic(assigns) do
    ~H"""
    <section aria-labelledby="ntfy-heading">
      <h2 id="ntfy-heading">ntfy</h2>
      <div :if={is_nil(@topic)}>
        <p>
          ntfy is a free app for phones and computers that shows alerts. Rescord can send your notifications there, to a private address of your own. A notification says only that there is something new, and for which organisation.
        </p>
        <p><button type="button" phx-click="ntfy-start">Get notifications on ntfy</button></p>
      </div>
      <div :if={@topic}>
        <p>Subscribe to this address in the ntfy app:</p>
        <p><output id="ntfy-address" data-address>{@address}</output></p>
        <p>
          <small>
            Anyone who has the address can read what Rescord sends there. Keep it to yourself; a new address stops the old one.
          </small>
        </p>
        <.confirm id="ntfy-renew-step" summary="New address" icon="arrow-path">
          <p>The old address stops. Subscribe to the new one in the ntfy app.</p>
          <.button type="button" variant="danger" phx-click="ntfy-renew">
            Make a new address
          </.button>
        </.confirm>
        <.confirm id="ntfy-stop-step" summary="Stop notifications on ntfy" icon="no-symbol">
          <p>Rescord sends nothing more to the address.</p>
          <.button type="button" variant="danger" phx-click="ntfy-stop">
            Stop notifications on ntfy
          </.button>
        </.confirm>
      </div>
    </section>
    """
  end
end
