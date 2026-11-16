defmodule RescordWeb.SettingsLive do
  @moduledoc """
  The settings of an organisation, at `/o/<short name>/settings`.

  The time zone (ADR 0026) says what today is for the organisation: a date
  of an arrival is not after today, and the age of a resident counts to
  today. The number of days ahead (ADR 0033) says how far ahead the tasks of
  the routines exist. Each member reads the settings. An administrator and a
  root user change them.

  The page opens again after a change, so that each part of it reads the
  organisation again.
  """

  use RescordWeb, :live_view

  alias Rescord.{Accounts, Tasks}
  alias RescordWeb.{ResidentWords, TaskWords}

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
       form: to_form(%{"time_zone" => organisation.time_zone}, as: :settings),
       ahead_form:
         to_form(%{"task_days_ahead" => to_string(organisation.task_days_ahead)}, as: :ahead)
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

  def handle_event("save_ahead", %{"ahead" => %{"task_days_ahead" => days} = params}, socket)
      when is_binary(days) do
    organisation = socket.assigns.organisation

    case Accounts.set_organisation_task_days_ahead(organisation, days,
           actor: socket.assigns.current_user
         ) do
      {:ok, organisation} ->
        # The routines get their tasks up to the new day now, and not in an hour.
        Tasks.generate(organisation)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "The tasks of the routines exist #{TaskWords.days(organisation.task_days_ahead)} ahead now."
         )
         |> push_navigate(to: ~p"/o/#{organisation.short_name}/settings")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           ahead_form: to_form(params, as: :ahead)
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

      <section aria-labelledby="ahead-heading">
        <h2 id="ahead-heading">Tasks of the routines</h2>
        <.list>
          <:item title="The tasks exist">{TaskWords.days(@organisation.task_days_ahead)} ahead</:item>
        </.list>
        <p>
          Rescord makes the tasks of each routine this number of days ahead. A routine can have
          a number of its own. A smaller number here removes no task that exists.
        </p>

        <.form :if={@can_change?} for={@ahead_form} id="ahead" phx-submit="save_ahead">
          <.input
            field={@ahead_form[:task_days_ahead]}
            type="number"
            label="Days ahead, from 1 to 400"
            min="1"
            max="400"
            required
          />
          <footer><.button type="submit">Save the days ahead</.button></footer>
        </.form>
      </section>
    </Layouts.app>
    """
  end
end
