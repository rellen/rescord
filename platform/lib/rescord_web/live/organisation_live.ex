defmodule RescordWeb.OrganisationLive do
  @moduledoc """
  The first page of an organisation, at `/o/<short name>`.

  The live session opens it only for a member of the organisation and for a
  root user. It says who the person is here. The pages of the residents and
  the tasks come later.
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
    <Layouts.app flash={@flash} current_user={@current_user} organisation={@organisation}>
      <.header>
        {@organisation.name}
        <:subtitle>{role_words(@role)}</:subtitle>
      </.header>

      <p><a href={~p"/o/#{@organisation.short_name}/members"}>See the members</a>.</p>
    </Layouts.app>
    """
  end

  defp role_words(:root), do: "You are a root user. You can do anything here."
  defp role_words(:administrator), do: "You are an administrator of this organisation."
  defp role_words(:member), do: "You are a member of this organisation."
end
