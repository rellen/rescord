defmodule RescordWeb.SettingsLive do
  @moduledoc """
  The settings of an organisation, at `/o/<short name>/settings`.

  The time zone (ADR 0026) says what today is for the organisation: a date
  of an arrival is not after today, and the age of a resident counts to
  today. The language and region (ADR 0075) say how a page writes a date, a
  time of day and a number. The number of days ahead (ADR 0033) says how far ahead the tasks of
  the routines exist. The parts of a copy (ADR 0042) are the parts that a
  copy of a transferred resident holds at first. Each member reads the settings. An administrator and a
  root user change them. The last part says where Ruby, the assistant, stands
  (ADR 0069), with a link to its own page, `RescordWeb.RubySettingsLive`.

  The page opens again after a change, so that each part of it reads the
  organisation again.
  """

  use RescordWeb, :live_view

  import RescordWeb.AccountComponents
  import RescordWeb.RubyComponents, only: [settings_line: 1]

  alias Rescord.{Accounts, Ruby, Tasks}
  alias RescordWeb.{TaskWords, TransferWords}

  @impl true
  def mount(_params, _session, socket) do
    organisation = socket.assigns.organisation
    can_change? = Accounts.role_can_change_settings?(socket.assigns.role)

    {:ok,
     assign(socket,
       page_title: "Settings",
       problems: [],
       can_change?: can_change?,
       ruby: Ruby.status(organisation),
       today: Accounts.today(organisation),
       time_zones: if(can_change?, do: Accounts.time_zones(), else: []),
       form: to_form(%{"time_zone" => organisation.time_zone}, as: :settings),
       locale_form: to_form(%{"locale" => organisation.locale}, as: :locale),
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
           form: typed_form(params, as: :settings)
         )}
    end
  end

  def handle_event("save_locale", %{"locale" => %{"locale" => locale} = params}, socket)
      when is_binary(locale) do
    organisation = socket.assigns.organisation

    case Accounts.set_organisation_locale(organisation, locale,
           actor: socket.assigns.current_user
         ) do
      {:ok, organisation} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "The language and region are #{Accounts.locale_name(organisation.locale)} now."
         )
         |> push_navigate(to: ~p"/o/#{organisation.short_name}/settings")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           locale_form: typed_form(params, as: :locale)
         )}
    end
  end

  def handle_event("save_parts", params, socket) do
    organisation = socket.assigns.organisation

    parts =
      for text <- List.wrap(get_in(params, ["parts", "keys"])),
          {:ok, part} <- [TransferWords.part_of(text)],
          uniq: true,
          do: part

    case Accounts.set_organisation_transfer_parts(organisation, parts,
           actor: socket.assigns.current_user
         ) do
      {:ok, _organisation} ->
        {:noreply,
         socket
         |> put_flash(:info, "A copy of a transferred resident holds those parts at first now.")
         |> push_navigate(to: ~p"/o/#{organisation.short_name}/settings")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
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
           ahead_form: typed_form(params, as: :ahead)
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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:settings}
    >
      <.header>
        Settings
        <:subtitle>The settings of {@organisation.name}</:subtitle>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <.time_zone_setting
        organisation={@organisation}
        today={@today}
        can_change?={@can_change?}
        form={@form}
        time_zones={@time_zones}
      />

      <.locale_setting
        organisation={@organisation}
        can_change?={@can_change?}
        locale_form={@locale_form}
      />

      <.days_ahead_setting
        organisation={@organisation}
        can_change?={@can_change?}
        ahead_form={@ahead_form}
      />

      <.transfer_parts_setting organisation={@organisation} can_change?={@can_change?} />

      <.settings_line organisation={@organisation} status={@ruby} can_change?={@can_change?} />
    </Layouts.app>
    """
  end
end
