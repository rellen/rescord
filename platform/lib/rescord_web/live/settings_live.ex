defmodule RescordWeb.SettingsLive do
  @moduledoc """
  The settings of an organisation, at `/o/<short name>/settings`.

  The one setting is the time zone (ADR 0026). It says what today is for the
  organisation: a date of an arrival is not after today, and the age of a
  resident counts to today. Each member reads the setting. An administrator
  and a root user change it.

  The page opens again after a change, so that each part of it reads the
  organisation again.
  """

  use RescordWeb, :live_view

  alias Rescord.Accounts
  alias RescordWeb.ResidentWords

  @impl true
  def mount(_params, _session, socket) do
    organisation = socket.assigns.organisation
    can_change? = Accounts.role_can_change_settings?(socket.assigns.role)

    {:ok,
     assign(socket,
       page_title: "Settings",
       problems: [],
       can_change?: can_change?,
       today: Accounts.today(organisation),
       time_zones: if(can_change?, do: Accounts.time_zones(), else: []),
       form: to_form(%{"time_zone" => organisation.time_zone}, as: :settings)
     )}
  end

  @impl true
  def handle_event("save", %{"settings" => %{"time_zone" => zone} = params}, socket)
      when is_binary(zone) do
    organisation = socket.assigns.organisation

    case Accounts.set_organisation_time_zone(organisation, zone,
           actor: socket.assigns.current_user
         ) do
      {:ok, _organisation} ->
        {:noreply,
         socket
         |> put_flash(:info, "The time zone is #{zone} now.")
         |> push_navigate(to: ~p"/o/#{organisation.short_name}/settings")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           form: to_form(params, as: :settings)
         )}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Settings
        <:subtitle>The settings of {@organisation.name}</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <section aria-labelledby="time-zone-heading">
        <h2 id="time-zone-heading">Time zone</h2>
        <.list>
          <:item title="Time zone">{@organisation.time_zone}</:item>
          <:item title="Today here">{ResidentWords.date(@today)}</:item>
        </.list>
        <p>
          The time zone says what today is for {@organisation.name}: a date of an arrival or a
          departure is not after today, and the age of a resident counts to today.
        </p>

        <.form :if={@can_change?} for={@form} id="settings" phx-submit="save">
          <.input
            field={@form[:time_zone]}
            label="Time zone, for example Australia/Brisbane"
            list="time-zones"
            autocomplete="off"
            required
          />
          <datalist id="time-zones">
            <option :for={zone <- @time_zones} value={zone}></option>
          </datalist>
          <footer><.button type="submit">Save the time zone</.button></footer>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
