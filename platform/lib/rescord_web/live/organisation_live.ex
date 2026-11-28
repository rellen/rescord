defmodule RescordWeb.OrganisationLive do
  @moduledoc """
  The first page of an organisation, at `/o/<short name>` (ADR 0065).

  The live session opens it only for a member of the organisation and for a
  root user. It says who the person is here, and then what needs somebody
  now: the tasks that are overdue or due today, the stock to count or to
  order, the residents that are expected or late back, the locations over
  their capacity, and the transfers that wait for an answer. A person sees
  what they can read and can act on, and each row leads to the page where
  they act. Below that, the page leads to each part of the organisation.

  The page reads again each minute. The time alone makes a task overdue, so
  no write tells the page about it, and the same read finds what another
  member did.
  """

  use RescordWeb, :live_view

  import RescordWeb.AttentionComponents

  alias Rescord.{Accounts, Attention}

  # The time between two reads of what needs somebody.
  @every :timer.minutes(1)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, members} = Accounts.members([load: [:email]] ++ options(socket))

    if connected?(socket), do: Process.send_after(self(), :read_again, @every)

    {:ok,
     socket
     |> assign(
       page_title: socket.assigns.organisation.name,
       members: Enum.map(members, &{to_string(&1.email), &1.user_id})
     )
     |> assign_attention()}
  end

  defp options(socket) do
    [actor: socket.assigns.current_user, tenant: socket.assigns.organisation]
  end

  defp assign_attention(socket) do
    now = DateTime.utc_now()

    parts =
      Attention.parts(socket.assigns.organisation,
        actor: socket.assigns.current_user,
        role: socket.assigns.role,
        now: now
      )

    assign(socket, attention: parts, now: now)
  end

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:read_again, socket) do
    Process.send_after(self(), :read_again, @every)
    {:noreply, assign_attention(socket)}
  end

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

      <.attention
        parts={@attention}
        organisation={@organisation}
        now={@now}
        members={@members}
        user={@current_user}
      />

      <nav aria-labelledby="parts-heading">
        <h2 id="parts-heading">The parts of {@organisation.name}</h2>
        <ul data-links>
          <li><a href={~p"/o/#{@organisation.short_name}/tasks"}>See the tasks of today</a></li>
          <li><a href={~p"/o/#{@organisation.short_name}/routines"}>See the routines</a></li>
          <li>
            <a href={~p"/o/#{@organisation.short_name}/calendar"}>See the calendar feeds</a>
          </li>
          <li><a href={~p"/o/#{@organisation.short_name}/residents"}>See the residents</a></li>
          <li><a href={~p"/o/#{@organisation.short_name}/groups"}>See the groups</a></li>
          <li><a href={~p"/o/#{@organisation.short_name}/housing"}>See the housing</a></li>
          <li><a href={~p"/o/#{@organisation.short_name}/inventory"}>See the inventory</a></li>
          <li><a href={~p"/o/#{@organisation.short_name}/tools"}>Use the tools</a></li>
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
      </nav>
    </Layouts.app>
    """
  end

  defp role_words(:root), do: "You are a root user. You can do anything here."
  defp role_words(%{name: name}), do: "Your role in this organisation: #{name}."
end
