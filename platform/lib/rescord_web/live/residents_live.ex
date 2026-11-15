defmodule RescordWeb.ResidentsLive do
  @moduledoc """
  The residents of an organisation, at `/o/<short name>/residents`.

  Each member sees the list, with a search by name, a filter by sex and by
  status, and a sort. Rescord calculates the status of each resident at the
  instant of the read.
  """

  use RescordWeb, :live_view

  alias Rescord.Residents
  alias RescordWeb.ResidentWords

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Residents",
       can_register?: Residents.role_can?(socket.assigns.role, :resident, :register)
     )}
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
