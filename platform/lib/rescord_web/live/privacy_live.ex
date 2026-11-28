defmodule RescordWeb.PrivacyLive do
  @moduledoc """
  Privacy in an organisation, at `/o/<short name>/privacy` (ADR 0105).

  Each member reads what the organisation does with their data, asks it to
  erase their data, and sees their own requests. A person whose role has
  the power `privacy` also reads each request, the open ones first,
  records a request that came by email, by letter or in person, and keeps
  the settings of privacy. `?member=<id>` chooses the person of the form,
  for the button "Erase" of the members page. Each request has a page of
  its own, `RescordWeb.PrivacyRequestLive`, where it is erased, extended,
  refused or withdrawn.
  """

  use RescordWeb, :live_view

  import RescordWeb.PrivacyComponents

  alias Rescord.{Accounts, Privacy}

  @impl true
  def mount(_params, _session, socket) do
    organisation = socket.assigns.organisation
    can_manage? = Privacy.role_can?(socket.assigns.role, :record)

    {:ok,
     socket
     |> assign(page_title: "Privacy", problems: [], can_manage?: can_manage?)
     |> assign(today: Accounts.today(organisation))
     |> assign(can_change_settings?: Privacy.role_can?(socket.assigns.role, :change_settings))
     |> assign(
       can_new_notice?:
         Accounts.granted?(socket.assigns.role, Rescord.Accounts.Organisation, :new_notice_id)
     )
     |> assign_requests()
     |> assign_settings()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_record_form(socket, params["member"])}
  end

  defp options(socket),
    do: [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]

  defp assign_requests(socket) do
    {:ok, requests} = Privacy.requests(options(socket))
    {open, closed} = Enum.split_with(requests, &(&1.state == :received))
    own_id = socket.assigns.current_user.id

    assign(socket,
      open: Enum.sort_by(open, &due/1, Date),
      closed: closed,
      own: Enum.filter(requests, &(&1.user_id == own_id)),
      people: Accounts.labels(options(socket))
    )
  end

  defp assign_settings(socket) do
    settings = Privacy.settings(socket.assigns.organisation)

    form =
      to_form(
        %{
          "money_years" => to_string(settings.money_years),
          "pseudonymise_after_months" => to_string(settings.pseudonymise_after_months || ""),
          "closed_request_years" => to_string(settings.closed_request_years),
          "contact_name" => settings.contact_name || "",
          "contact_email" => to_string(settings.contact_email || ""),
          "authority" => settings.authority || "",
          "notice_text" => settings.notice_text || ""
        },
        as: :settings
      )

    assign(socket, settings: settings, settings_form: form)
  end

  # The people whose data a request can be about: each member, and each
  # former member who is not erased.
  defp choices(socket) do
    {:ok, members} = Accounts.members([load: [:email]] ++ options(socket))
    former = Accounts.former_members(options(socket))

    Enum.map(members, &{to_string(&1.email), &1.id}) ++
      Enum.map(former, &{"#{&1.email} (former member)", &1.id})
  end

  defp assign_record_form(socket, member_id) do
    if socket.assigns.can_manage? do
      choices = choices(socket)
      chosen = if Enum.any?(choices, &(elem(&1, 1) == member_id)), do: member_id, else: ""

      assign(socket,
        choices: choices,
        record_form:
          to_form(
            %{
              "member_id" => chosen,
              "how_received" => "email",
              "identity" => "",
              "received_on" => Date.to_iso8601(socket.assigns.today),
              "identity_confirmed_on" => "",
              "contact" => ""
            },
            as: :request
          )
      )
    else
      assign(socket, choices: [], record_form: nil)
    end
  end

  @impl true
  def handle_event("ask", _params, socket) do
    case Privacy.ask(%{}, options(socket)) do
      {:ok, request} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_requests()
         |> put_flash(
           :info,
           "Your request is recorded. #{socket.assigns.organisation.name} answers by #{RescordWeb.ResidentWords.date(request.due_on)}."
         )}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  def handle_event("record", %{"request" => params}, socket) when is_map(params) do
    fields =
      params
      |> Map.take([
        "member_id",
        "how_received",
        "identity",
        "received_on",
        "identity_confirmed_on",
        "contact"
      ])
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)

    case Privacy.record_request(fields, options(socket)) do
      {:ok, request} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/o/#{socket.assigns.organisation.short_name}/privacy/#{request.id}"
         )}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           record_form: to_form(params, as: :request)
         )}
    end
  end

  def handle_event("save_settings", %{"settings" => params}, socket) when is_map(params) do
    fields =
      params
      |> Map.take(
        ~w(money_years pseudonymise_after_months closed_request_years contact_name contact_email authority notice_text)
      )
      |> Map.new(fn {key, value} -> {key, if(value == "", do: nil, else: value)} end)

    case Privacy.save_settings(fields, options(socket)) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> assign(problems: [])
         |> assign_settings()
         |> put_flash(:info, "The settings of privacy are saved.")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           problems: Accounts.error_messages(error),
           settings_form: to_form(params, as: :settings)
         )}
    end
  end

  def handle_event("new_notice_id", _params, socket) do
    case Accounts.new_notice_id(socket.assigns.organisation, actor: socket.assigns.current_user) do
      {:ok, organisation} ->
        {:noreply,
         socket
         |> assign(organisation: organisation, problems: [])
         |> put_flash(:info, "The notice has a new link. The old one no longer works.")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Accounts.error_messages(error))}
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      inbox={@inbox}
      ruby={@ruby?}
      section={:members}
    >
      <.header icon={Icons.section(:privacy)}>
        Privacy
        <:subtitle>Requests to erase data in {@organisation.name}</:subtitle>
      </.header>

      <.problems list={@problems} />

      <section id="own-data" aria-labelledby="own-heading">
        <h2 id="own-heading">Your data</h2>
        <p>
          {@organisation.name} keeps your email address with the records you write and the
          changes you make, so that it knows who cared for each animal. You can ask it to erase
          your data. It then replaces your name on its records with "Former member" and a
          number, and keeps what the law requires, such as money records. It answers within
          one calendar month.
        </p>
        <.requests
          :if={@own != []}
          id="own-requests"
          requests={@own}
          people={@people}
          organisation={@organisation}
          today={@today}
          empty=""
        />
        <.confirm
          :if={@member && not Enum.any?(@own, &(&1.state == :received))}
          id="ask-step"
          summary={"Ask #{@organisation.name} to erase my data"}
        >
          <p>
            A person there answers within one month, and the erasure cannot be undone.
          </p>
          <.button id="ask" variant="danger" phx-click="ask">
            Ask {@organisation.name} to erase my data
          </.button>
        </.confirm>
      </section>

      <section :if={@can_manage?} id="open" aria-labelledby="open-heading">
        <h2 id="open-heading">Requests that wait</h2>
        <.requests
          id="open-requests"
          requests={@open}
          people={@people}
          organisation={@organisation}
          today={@today}
          empty="No request waits."
        />
      </section>

      <.record_form :if={@can_manage?} form={@record_form} choices={@choices} />

      <section :if={@can_manage?} id="closed" aria-labelledby="closed-heading">
        <h2 id="closed-heading">Closed requests</h2>
        <p>
          A closed request stays for {@settings.closed_request_years} years, as the proof of what {@organisation.name} did and when.
        </p>
        <.requests
          id="closed-requests"
          requests={@closed}
          people={@people}
          organisation={@organisation}
          today={@today}
          empty="No request is closed."
        />
      </section>

      <.settings
        :if={@can_manage?}
        form={@settings_form}
        can_change?={@can_change_settings?}
        settings={@settings}
      />

      <section :if={@can_manage?} id="notice-link" aria-labelledby="notice-heading">
        <h2 id="notice-heading">The privacy notice</h2>
        <p>
          Each person reads the notice of {@organisation.name} at this link, with no sign-in. The
          link holds a random id that says nothing else about {@organisation.name}. Give it to
          your members and volunteers.
        </p>
        <p>
          <.link href={~p"/privacy/#{@organisation.notice_id}"}>{url(
            ~p"/privacy/#{@organisation.notice_id}"
          )}</.link>
        </p>
        <.confirm
          :if={@can_new_notice?}
          id="new-notice-step"
          summary="Make a new link"
          icon="arrow-path"
        >
          <p>The old link stops working at once.</p>
          <.button id="new-notice-id" variant="danger" phx-click="new_notice_id">
            Make a new link and end the old one
          </.button>
        </.confirm>
      </section>
    </Layouts.app>
    """
  end
end
