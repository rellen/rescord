defmodule RescordWeb.ResidentsLive do
  @moduledoc """
  The residents of an organisation, at `/o/<short name>/residents`.

  Each member sees the list, with a search by name, a filter by sex and by
  status, and a sort. Rescord calculates the status of each resident at the
  instant of the read.

  The profile picture of each resident shows beside its name (ADR 0055).
  Cinder reads the residents, and the pictures are in another domain, so
  the page reads the pictures of the organisation once, when it opens.
  """

  use RescordWeb, :live_view

  alias Rescord.{Photos, Residents}
  alias RescordWeb.{PhotoComponents, ResidentWords}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Residents",
       portraits: portraits(socket),
       can_register?: Residents.role_can?(socket.assigns.role, :resident, :register)
     )}
  end

  # The link to the thumbnail of the profile picture of each resident that has
  # one, by the id of the resident. A person who cannot read the pictures
  # gets none, and the page shows the list without them.
  defp portraits(socket) do
    organisation = socket.assigns.organisation

    case Photos.all_profile_photos(actor: socket.assigns.current_user, tenant: organisation) do
      {:ok, photos} ->
        Map.new(photos, fn {resident_id, photo} ->
          {resident_id, PhotoComponents.thumbnail_url(organisation, photo)}
        end)

      {:error, _error} ->
        %{}
    end
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        Residents
        <:subtitle>The animals in the care of {@organisation.name}</:subtitle>
        <:actions>
          <.link
            :if={@can_register?}
            navigate={~p"/o/#{@organisation.short_name}/residents/new"}
            data-variant="primary"
          >
            New resident
          </.link>
        </:actions>
      </.header>

      <Cinder.collection
        id="residents"
        query={
          Residents.query_to_residents(%{},
            load: Residents.summary(),
            query: [sort: [name: :asc]],
            actor: @current_user,
            tenant: @organisation
          )
        }
        actor={@current_user}
        tenant={@organisation}
      >
        <:col :let={resident} field="name" label="Name" sort search>
          <.link navigate={~p"/o/#{@organisation.short_name}/residents/#{resident.id}"}>
            <PhotoComponents.portrait url={@portraits[resident.id]} name={resident.name} />
            {resident.name || "No name yet"}
          </.link>
        </:col>
        <:col :let={resident} field="species_label" label="Species" sort>
          {resident.species_label}
        </:col>
        <:col
          :let={resident}
          field="sex"
          label="Sex"
          filter={[type: :select, prompt: "Any sex", options: ResidentWords.options(:sex)]}
        >
          {ResidentWords.sex(resident.sex)}
        </:col>
        <:col
          :let={resident}
          field="status"
          label="Status"
          filter={[type: :select, prompt: "Any status", options: ResidentWords.options(:status)]}
        >
          <.state kind={ResidentWords.status_kind(resident.status)}>
            {ResidentWords.status(resident.status)}
          </.state>
        </:col>
        <:col :let={resident} field="arrived_on" label="Arrived" sort>
          {ResidentWords.date(resident.arrived_on) || "Not yet"}
        </:col>
      </Cinder.collection>
    </Layouts.app>
    """
  end
end
