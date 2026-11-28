defmodule RescordWeb.ResidentLive do
  @moduledoc """
  One resident, at `/o/<short name>/residents/<id>`.

  The page shows each fact of the resident, and its stay: the arrival, an
  absence, and the departure. A member records each of those here, and adds
  or removes an identifier. The policy of each resource decides when the
  action runs.

  A resident that the person cannot read, and one that is not there, give
  the same answer: the list of the residents.
  """

  use RescordWeb, :live_view

  import RescordWeb.ResidentComponents

  alias Rescord.{Journal, Lists, Locations, Photos, Residents}
  alias RescordWeb.ResidentWords

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case load(socket, id) do
      {:ok, socket} ->
        {:ok, kinds} = Lists.offered_values(:identifier_kind, options(socket))

        {:ok,
         socket
         |> assign(problems: [], today: Rescord.Accounts.today(socket.assigns.organisation))
         |> assign(identifier_kinds: Enum.map(kinds, &{to_string(&1.label), &1.id}))
         |> assign_forms()}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such resident.")
         |> redirect(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}
    end
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp load(socket, id) do
    with true <- is_binary(id),
         {:ok, %{} = resident} <- Residents.resident_with_facts(id, options(socket)) do
      {:ok,
       assign(socket,
         resident: resident,
         page_title: resident.name || "A resident with no name",
         names: Residents.name_history(resident.id, options(socket)),
         desex_statuses: Residents.desex_history(resident.id, options(socket)),
         relations: Residents.relations(resident.id, options(socket)),
         homes: homes(resident.id, options(socket)),
         measurements: measurements(resident.id, options(socket)),
         profile_photo: profile_photo(resident.id, options(socket))
       )
       |> assign_choices()}
    else
      _no_resident -> :error
    end
  end

  # The residents and the families that a form of the relations offers.
  defp assign_choices(socket) do
    {:ok, residents} = Residents.residents([load: [:name]] ++ options(socket))
    {:ok, families} = Residents.families(options(socket))
    relations = socket.assigns.relations
    in_family = MapSet.new(relations.families, & &1.family_id)

    assign(socket,
      other_residents:
        residents
        |> Enum.reject(&(&1.id == socket.assigns.resident.id))
        |> Enum.map(&{&1.name || "No name yet", &1.id})
        |> Enum.sort(),
      other_families:
        families
        |> Enum.reject(&MapSet.member?(in_family, &1.id))
        |> Enum.map(&{&1.name, &1.id})
        |> Enum.sort(),
      parent_form: to_form(%{"parent_id" => "", "role" => "mother"}, as: :parent),
      family_form: to_form(%{"family_id" => "", "name" => ""}, as: :family)
    )
  end

  # The profile picture of the resident, or nil (ADR 0055).
  defp profile_photo(resident_id, options) do
    {:ok, photo} = Photos.profile_photo(resident_id, options)
    photo
  end

  # The newest measurement of each kind, for example the weight.
  defp measurements(resident_id, options) do
    {:ok, latest} = Journal.latest_measurements(resident_id, options)
    latest
  end

  defp homes(resident_id, options) do
    {:ok, homes} = Locations.home(resident_id, options)
    homes
  end

  defp assign_forms(socket) do
    today = Date.to_iso8601(socket.assigns.today)

    assign(socket,
      arrival_form: to_form(%{"kind" => "", "arrived_on" => today, "note" => ""}, as: :arrival),
      departure_form:
        to_form(%{"kind" => "", "departed_on" => today, "note" => ""}, as: :departure),
      absence_form: to_form(%{"reason" => "", "expected_back_on" => ""}, as: :absence),
      identifier_form: to_form(%{"kind_id" => "", "value" => ""}, as: :identifier)
    )
  end

  @impl true
  def handle_event("record_arrival", %{"arrival" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      kind: params["kind"],
      arrived_on: params["arrived_on"],
      note: non_blank(params["note"])
    }
    |> Residents.record_arrival(options(socket))
    |> after_write(socket, "The arrival is recorded.")
  end

  def handle_event("record_departure", %{"departure" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      kind: params["kind"],
      departed_on: params["departed_on"],
      note: non_blank(params["note"])
    }
    |> Residents.record_departure(options(socket))
    |> after_write(socket, "The departure is recorded.")
  end

  def handle_event("withdraw_departure", _params, socket) do
    case socket.assigns.resident.departure do
      nil ->
        {:noreply, socket}

      departure ->
        departure |> Residents.withdraw_departure(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("start_absence", %{"absence" => params}, socket) when is_map(params) do
    at(socket, params["at"], fn options ->
      Residents.start_absence(
        %{
          resident_id: socket.assigns.resident.id,
          reason: params["reason"],
          expected_back_on: non_blank(params["expected_back_on"])
        },
        options
      )
    end)
  end

  def handle_event("finish_absence", params, socket) do
    case socket.assigns.resident.absence do
      nil ->
        {:noreply, socket}

      absence ->
        at(socket, get_in(params, ["back", "at"]), &Residents.finish_absence(absence, &1))
    end
  end

  def handle_event("add_identifier", %{"identifier" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      kind_id: non_blank(params["kind_id"]),
      value: params["value"]
    }
    |> Residents.add_identifier(options(socket))
    |> after_write(socket)
  end

  def handle_event("record_parent", %{"parent" => params}, socket) when is_map(params) do
    %{
      resident_id: socket.assigns.resident.id,
      parent_id: non_blank(params["parent_id"]),
      role: params["role"]
    }
    |> Residents.record_parent(options(socket))
    |> after_write(socket)
  end

  def handle_event("remove_parent", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.relations.parents, &(&1.id == id)) do
      nil -> {:noreply, socket}
      link -> link |> Residents.remove_parent(options(socket)) |> after_write(socket)
    end
  end

  # A family that is there, or a new one with the name that the person gave.
  def handle_event("add_to_family", %{"family" => params}, socket) when is_map(params) do
    family =
      case {non_blank(params["family_id"]), non_blank(params["name"])} do
        {nil, nil} -> {:error, :nothing}
        {nil, name} -> Residents.name_family(name, options(socket))
        {id, _name} -> {:ok, %{id: id}}
      end

    case family do
      {:ok, %{id: family_id}} ->
        %{resident_id: socket.assigns.resident.id, family_id: family_id}
        |> Residents.add_to_family(options(socket))
        |> after_write(socket)

      {:error, :nothing} ->
        {:noreply, assign(socket, problems: ["Choose a family, or give a new one a name"])}

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
  end

  def handle_event("remove_from_family", %{"id" => id}, socket) when is_binary(id) do
    case Enum.find(socket.assigns.relations.families, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      membership ->
        membership |> Residents.remove_from_family(options(socket)) |> after_write(socket)
    end
  end

  def handle_event("remove_resident", _params, socket) do
    case Residents.remove_resident(socket.assigns.resident, options(socket)) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "The resident is removed.")
         |> push_navigate(to: ~p"/o/#{socket.assigns.organisation.short_name}/residents")}

      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}
    end
  end

  def handle_event("remove_identifier", %{"id" => id}, socket) when is_binary(id) do
    # Only an identifier of this resident: the page has them in hand.
    case Enum.find(socket.assigns.resident.identifiers, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      identifier ->
        identifier |> Residents.remove_identifier(options(socket)) |> after_write(socket)
    end
  end

  # Ignore an event that this page does not know.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # Opens the page again after a write, or shows what was wrong. A new page
  # reads the resident again, and its forms are empty: a form that stays on
  # the page keeps what the person typed.
  # Runs a write at the time that the member gave, which is a local time of
  # the organisation and never after now, or at this instant with no time.
  defp at(socket, text, write) do
    case Rescord.Accounts.instant(socket.assigns.organisation, text) do
      {:ok, nil} -> socket |> options() |> write.() |> after_write(socket)
      {:ok, instant} -> ([as_of: instant] ++ options(socket)) |> write.() |> after_write(socket)
      {:error, words} -> {:noreply, assign(socket, problems: [words])}
    end
  end

  defp after_write(result, socket, words \\ nil) do
    case result do
      {:error, error} ->
        {:noreply, assign(socket, problems: Rescord.Accounts.error_messages(error))}

      _done ->
        socket = if words, do: put_flash(socket, :info, words), else: socket

        {:noreply,
         push_navigate(socket,
           to:
             ~p"/o/#{socket.assigns.organisation.short_name}/residents/#{socket.assigns.resident.id}"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      organisation={@organisation}
      section={:residents}
    >
      <nav aria-label="Breadcrumb">
        <.link navigate={~p"/o/#{@organisation.short_name}/residents"}>Residents</.link>
      </nav>

      <.header>
        {@resident.name || "A resident with no name"}
        <:subtitle>
          {@resident.species.label} · {ResidentWords.sex(@resident.sex)} ·
          <.state kind={ResidentWords.status_kind(@resident.status)}>
            {ResidentWords.status(@resident.status)}
          </.state>
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/photos"}
            data-variant="secondary"
          >
            Photos
          </.link>
          <.link
            :if={can?(@role, :resident, :revise)}
            navigate={~p"/o/#{@organisation.short_name}/residents/#{@resident.id}/edit"}
            data-variant="secondary"
          >
            Change the facts
          </.link>
        </:actions>
      </.header>

      <p :for={problem <- @problems} role="alert">{problem}</p>

      <RescordWeb.PhotoComponents.profile
        photo={@profile_photo}
        organisation={@organisation}
        resident={@resident}
      />

      <.about resident={@resident} today={@today} />

      <.stay
        homes={@homes}
        organisation={@organisation}
        resident={@resident}
        role={@role}
        arrival_form={@arrival_form}
        absence_form={@absence_form}
        departure_form={@departure_form}
      />

      <.journal_summary
        measurements={@measurements}
        organisation={@organisation}
        resident={@resident}
      />

      <.relations
        relations={@relations}
        organisation={@organisation}
        role={@role}
        other_residents={@other_residents}
        parent_form={@parent_form}
        family_form={@family_form}
        other_families={@other_families}
      />

      <.identifiers
        resident={@resident}
        role={@role}
        identifier_kinds={@identifier_kinds}
        identifier_form={@identifier_form}
      />

      <.facts_history
        :if={length(@names) > 1 or length(@desex_statuses) > 1}
        names={@names}
        organisation={@organisation}
        desex_statuses={@desex_statuses}
      />
      <RescordWeb.ReportComponents.resident_documents
        organisation={@organisation}
        resident={@resident}
      />
      <.removal :if={can?(@role, :resident, :remove)} />
    </Layouts.app>
    """
  end
end
