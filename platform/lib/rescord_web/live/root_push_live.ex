defmodule RescordWeb.RootPushLive do
  @moduledoc """
  The notifications that leave the server, for a root user, at
  `/root/push` (issue 29, ADR 0106): the keys of Web Push and the contact
  for the push services, and the server of ntfy with its access token. The
  live session lets only a root user in, and the policy of
  `Rescord.Notifications.Settings` refuses each other person.

  No setting of the channels is in the environment (ADR 0068): this page
  is where they are set. The private key of Web Push is made here, and
  never shown. The token of ntfy goes from its form to the action and
  nowhere else: no assign holds it, and the page never sends one back.
  """

  use RescordWeb, :live_view

  alias Rescord.Notifications
  alias RescordWeb.ResidentWords

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Notifications on devices", problems: [], token_problems: [])
     |> load()}
  end

  defp options(socket), do: [actor: socket.assigns.current_user]

  defp load(socket) do
    settings = Notifications.settings(options(socket))

    assign(socket,
      settings: settings,
      devices: Notifications.device_count(),
      form: form_of(settings)
    )
  end

  defp form_of(settings) do
    to_form(
      %{
        "contact" => settings.contact || "",
        "push_on" => to_string(settings.push_on || false),
        "ntfy_url" => settings.ntfy_url || "",
        "ntfy_on" => to_string(settings.ntfy_on || false)
      },
      as: :settings
    )
  end

  @impl true
  def handle_event("save", %{"settings" => %{} = fields}, socket) do
    attributes = %{
      contact: non_blank(fields["contact"]),
      push_on: fields["push_on"] == "true",
      ntfy_url: non_blank(fields["ntfy_url"]),
      ntfy_on: fields["ntfy_on"] == "true"
    }

    case Notifications.save_settings(attributes, options(socket)) do
      {:ok, _settings} ->
        {:noreply, socket |> assign(problems: []) |> put_flash(:info, "Saved.") |> load()}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: words(error),
           form: to_form(Shoddy.Maps.text_fields(fields), as: :settings)
         )}
    end
  end

  def handle_event("make-keys", _params, socket) do
    case Notifications.make_keys(options(socket)) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> put_flash(
           :info,
           "The server has new keys. Each person turns notifications on again on each device."
         )
         |> load()}

      {:error, error} ->
        {:noreply, assign(socket, problems: words(error))}
    end
  end

  def handle_event("save-token", %{"ntfy" => %{"token" => token}}, socket) do
    case Notifications.save_ntfy_token(non_blank(token) || "", options(socket)) do
      {:ok, _settings} ->
        {:noreply,
         socket |> assign(token_problems: []) |> put_flash(:info, "Saved the token.") |> load()}

      {:error, error} ->
        {:noreply, assign(socket, token_problems: words(error))}
    end
  end

  def handle_event("forget-token", _params, socket) do
    case Notifications.forget_ntfy_token(socket.assigns.settings, options(socket)) do
      {:ok, _settings} ->
        {:noreply, socket |> put_flash(:info, "The server has no token of ntfy now.") |> load()}

      {:error, error} ->
        {:noreply, assign(socket, token_problems: words(error))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp words(error), do: for({_field, words} <- Notifications.problems(error), do: words)

  defp made(nil), do: nil
  defp made(%DateTime{} = at), do: ResidentWords.date(DateTime.to_date(at))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} section={:root}>
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/root"}>Root</.link>
      </nav>

      <.header>
        Notifications on devices
        <:subtitle>
          <.state :if={@settings.push_on} kind="ok">Devices on</.state>
          <.state :if={!@settings.push_on} kind="none">Devices off</.state>
          ·
          <.state :if={@settings.ntfy_on} kind="ok">ntfy on</.state>
          <.state :if={!@settings.ntfy_on} kind="none">ntfy off</.state>
          · {@devices} {if @devices == 1, do: "device", else: "devices"}
        </:subtitle>
      </.header>

      <.problems list={@problems} />

      <section aria-labelledby="keys-heading">
        <h2 id="keys-heading">The keys of this server</h2>
        <p>
          A push service delivers a notification of this server only with its key. The private key is encrypted in the database, and no page shows it.
        </p>
        <dl :if={@settings.vapid_public_key}>
          <dt>Public key</dt>
          <dd>
            <code>{@settings.vapid_public_key}</code>, made on {made(@settings.keys_made_at)}
          </dd>
        </dl>
        <p :if={is_nil(@settings.vapid_public_key)}>
          <button type="button" phx-click="make-keys">Make the keys</button>
        </p>
        <details :if={@settings.vapid_public_key} id="new-keys">
          <summary>Make new keys</summary>
          <p>
            Each device stops getting notifications, and each person turns them on again on the device. Do this only when the private key may have left the server.
          </p>
          <button
            type="button"
            data-variant="danger"
            phx-click="make-keys"
            data-confirm="Make new keys? Each device stops getting notifications."
          >
            Make new keys and end each subscription
          </button>
        </details>
      </section>

      <.form for={@form} id="push-settings" phx-submit="save">
        <h2>Sending</h2>
        <.input
          field={@form[:contact]}
          type="text"
          label="Contact for the push services"
          hint="An address that starts with mailto: or https://. Apple, Google, Mozilla and Microsoft can write to it about the notifications of this server."
        />
        <.input
          field={@form[:push_on]}
          type="checkbox"
          label="Send notifications to devices"
          hint="A notification holds the name of the organisation and one sentence of its kind, encrypted for the device. It names no resident, no person and no words of a comment."
        />
        <.input
          field={@form[:ntfy_url]}
          type="url"
          label="Server of ntfy"
          placeholder="https://ntfy.sh"
          hint="The address of a server of ntfy, which starts with https://. Each person gets a topic of their own there, with a name that nobody can guess."
        />
        <.input
          field={@form[:ntfy_on]}
          type="checkbox"
          label="Send notifications to ntfy"
          hint="ntfy gets the name of the organisation, one sentence of its kind and a link to the page of notifications, with no encryption of its own. A server of your own keeps that with you."
        />
        <footer><button type="submit">Save</button></footer>
      </.form>

      <form id="ntfy-token" phx-submit="save-token">
        <h2>The access token of ntfy</h2>
        <p :if={@settings.ntfy_token_set_at}>
          The server has a token, set on {made(@settings.ntfy_token_set_at)}. No page shows it.
        </p>
        <p :if={is_nil(@settings.ntfy_token_set_at)}>
          A server of ntfy that lets only its users write needs a token. ntfy.sh needs none.
        </p>
        <.problems list={@token_problems} />
        <.input
          id="ntfy-token-field"
          name="ntfy[token]"
          type="password"
          label={if @settings.ntfy_token_set_at, do: "A new token", else: "The token"}
          value=""
          autocomplete="off"
        />
        <footer>
          <button type="submit">Save the token</button>
          <button
            :if={@settings.ntfy_token_set_at}
            type="button"
            data-variant="secondary"
            phx-click="forget-token"
          >
            Forget the token
          </button>
        </footer>
      </form>
    </Layouts.app>
    """
  end
end
