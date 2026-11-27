defmodule RescordWeb.OrganisationLive do
  @moduledoc """
  The first page of an organisation, at `/o/<short name>`.

  The live session opens it only for a member of the organisation and for a
  root user. It says who the person is here, and leads to the residents, the
  lists and the members.
  """

  use RescordWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: socket.assigns.organisation.name)}
  end

  @impl true
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
      section={:home}
    >
      <.header>
        {@organisation.name}
        <:subtitle>{role_words(@role)}</:subtitle>
      </.header>

      <ul data-links>
        <li><a href={~p"/o/#{@organisation.short_name}/tasks"}>See the tasks of today</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/routines"}>See the routines</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/residents"}>See the residents</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/groups"}>See the groups</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/housing"}>See the housing</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/inventory"}>See the inventory</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/lists"}>See the lists of values</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/members"}>See the members</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/roles"}>See the roles</a></li>
        <li>
          <a href={~p"/o/#{@organisation.short_name}/transfers"}>See the transfers</a>
        </li>
        <li>
          <a href={~p"/o/#{@organisation.short_name}/partners"}>See the partner refuges</a>
        </li>
        <li><a href={~p"/o/#{@organisation.short_name}/settings"}>See the settings</a></li>
        <li><a href={~p"/o/#{@organisation.short_name}/export"}>Export the data</a></li>
      </ul>
    </Layouts.app>
    """
  end

  defp role_words(:root), do: "You are a root user. You can do anything here."
  defp role_words(%{name: name}), do: "Your role in this organisation: #{name}."
end
